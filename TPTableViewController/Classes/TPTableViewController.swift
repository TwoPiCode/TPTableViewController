//
//  TPTableViewController.swift
//  TPTableViewController
//

// TODO: list
// - Reduce drag distance for pull to refresh
// - Spinner background color - maybe it should be on the right so it doesn't obscure the search,
//   but also make sure not to obscure the clear button

import UIKit

open class TPTableViewController: UIViewController {
    public var tableView = UITableView()

    public var backgroundColor = UIColor.groupTableViewBackground

    public var data: [TPTableData]? {
        didSet {
            if data != nil {
                hasLoadedInitialData = true
            }
            if paginationIsEnabled {
                filteredData = data
            }
            DispatchQueue.main.async {
                if !self.paginationIsEnabled {
                    self.filterAndSetData()
                }

                self.setNoContentLabel()
                self.tableView.reloadData()
            }
        }
    }

    public var filteredData: [TPTableData]? {
        didSet {
            DispatchQueue.main.async {
                if !self.paginationIsEnabled {
                    self.setNoContentLabel()
                }
                self.tableView.reloadData()
            }
        }
    }

    public var currentRequest: URLSessionDataTask? {
        didSet {
            oldValue?.cancel()
        }
    }

    // TODO: enable switching
    public var scopeStrings: [String] = []
    public var segmentedControl = UISegmentedControl()

    // Wrapper views
    var searchWrapperView = UIView()
    var segmentedControlWrapperView = UIView()

    // search bar
    public var searchTerms = ""
    public var searchWasCancelled = false

    // pagination
    public var paginationIsEnabled = false
    var previousQuery = ""
    public var noMoreResults = false
    public let itemsPerPage = 20
    var pagesLoaded: Int {
        return Int((data?.count ?? 0) / itemsPerPage)
    }

    public var deselectCellOnWillAppear = true

    var hasLoadedInitialData = false

    open weak var delegate: TPTableViewDelegate? {
        didSet {}
    }

    open weak var segmentedControlDelegate: TPTableViewSegmentedControlDelegate?

    public var releaseToRefreshText: String {
        if delegate?.itemName != nil, let text = delegate?.itemName?() {
            return "Release to refresh \(text.lowercased())"
        } else {
            return "Release to refresh data"
        }
    }

    public var pullToRefreshText: String {
        if delegate?.itemName != nil, let text = delegate?.itemName?() {
            return "Pull to refresh \(text.lowercased())"
        } else {
            return "Pull to refresh data"
        }
    }

    public var refreshingDataText: String {
        if delegate?.itemName != nil, let text = delegate?.itemName?() {
            return "Loading \(text.lowercased())..."
        } else {
            return "Loading data..."
        }
    }

    // Set to true when the API is loading data
    public var isLoadingData: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.searchController.searchBar.isLoading = self.isLoadingData
            }
        }
    }

    open weak var dataSource: TPTableViewDataSource?
    open weak var filterDelegate: TPTableViewFilterDelegate?

    open var refreshControl = UIRefreshControl()
    open var searchController = UISearchController()

    var style: UITableView.Style = .plain

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    public init(style: UITableView.Style = .plain) {
        super.init(nibName: nil, bundle: nil)
        self.style = style
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        if let itemName = delegate?.itemName?() {
            title = itemName
        }

        setupSearchBar()
    }

    var hasSetupTable = false

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !hasSetupTable {
            hasSetupTable = true

            setupTableView()
            setupRefreshControl()

            layoutView()
        }

        if deselectCellOnWillAppear, let selectionIndex = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectionIndex, animated: true)
        }
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // This was causing some weird transitions with the navigation controller pushing and popping
        // Not sure if this should be placed in view will appear, or safe to just remove entirely.
        // UI looks to be otherwise ok at the moment.

        //        if let navBar = navigationController?.navigationBar {
        //            // To get transparent navigationBar
        //            navBar.setBackgroundImage(UIImage(), for: UIBarPosition.any, barMetrics: UIBarMetrics.default)
        //            // To remove black hairline under the Navigationbar
        //            navBar.shadowImage = UIImage()
        //            navBar.isTranslucent = false
        //        }

        //        self.searchController.searchBar.barTintColor = backgroundColor
        //        self.searchController.searchBar.backgroundColor = self.backgroundColor

        // bit of a hack
        //        self.searchController.searchBar.layer.borderWidth = 1
        //        self.searchController.searchBar.layer.borderColor = self.backgroundColor.cgColor

        //        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {

        if !hasLoadedInitialData {
            refreshData()
        }

        //        }
    }

    func layoutView() {
        // these constraints are always needed
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        // if iOS <11 then we need to layout the searchbar
        if #available(iOS 11, *) {} else {
            let searchBar = searchController.searchBar
            searchWrapperView.topAnchor.constraint(equalTo: searchBar.topAnchor).isActive = true
            searchWrapperView.leftAnchor.constraint(equalTo: searchBar.leftAnchor).isActive = true
            searchWrapperView.rightAnchor.constraint(equalTo: searchBar.rightAnchor).isActive = true
            searchWrapperView.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor).isActive = true

            searchWrapperView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            searchWrapperView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            searchWrapperView.topAnchor.constraint(equalTo: topLayoutGuide.topAnchor).isActive = true
        }

        // if we're showing a scope selector, then we want to add it below the navbar
        if scopeStrings.count != 0 {
            segmentedControlWrapperView.translatesAutoresizingMaskIntoConstraints = false
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false

            segmentedControlWrapperView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            segmentedControlWrapperView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true

            // If iOS >= 11 searchbar bottom is the same as topAnchor
            if #available(iOS 11, *) {
                segmentedControlWrapperView.topAnchor.constraint(equalTo: topLayoutGuide.topAnchor).isActive = true
            } else {
                segmentedControlWrapperView.topAnchor.constraint(equalTo: searchWrapperView.bottomAnchor).isActive = true
            }

            segmentedControl.centerXAnchor.constraint(equalTo: segmentedControlWrapperView.centerXAnchor).isActive = true
            segmentedControl.centerYAnchor.constraint(equalTo: segmentedControlWrapperView.centerYAnchor).isActive = true
            segmentedControl.topAnchor.constraint(equalTo: segmentedControlWrapperView.topAnchor, constant: 8).isActive = true
            segmentedControl.bottomAnchor.constraint(equalTo: segmentedControlWrapperView.bottomAnchor, constant: -8).isActive = true
            segmentedControl.leftAnchor.constraint(equalTo: segmentedControlWrapperView.leftAnchor, constant: 8).isActive = true
            segmentedControl.rightAnchor.constraint(equalTo: segmentedControlWrapperView.rightAnchor, constant: -8).isActive = true

            tableView.topAnchor.constraint(equalTo: segmentedControlWrapperView.bottomAnchor).isActive = true
        } else {
            // tableview top is searchbar bottom
            // If iOS >= 11 searchbar bottom is the same as topAnchor
            if #available(iOS 11, *) {
                tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            } else {
                tableView.topAnchor.constraint(equalTo: searchWrapperView.bottomAnchor).isActive = true
            }
        }
    }

    func setupTableView() {
        tableView = UITableView(frame: view.frame, style: style)

        delegate?.registerReusableCell()

        // Setup tableview
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = UIColor.groupTableViewBackground
        tableView.keyboardDismissMode = .onDrag

        tableView.rowHeight = UITableView.automaticDimension
        // It'd be a good idea to set this in the subclasses, and make sure this doesn't override it
        tableView.estimatedRowHeight = 44

        let footerFrame = CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 1)
        tableView.tableFooterView = UIView(frame: footerFrame)

        // Start: Add tableview, add constraints
        view.addSubview(tableView)

        if scopeStrings.count != 0 {
            setupSegmentedControl()
        }

        tableView.allowsSelection = delegate?.didSelectRowAt != nil
    }

    func setupSegmentedControl() {
        segmentedControlWrapperView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)) // will get set in autolayout

        segmentedControlWrapperView.backgroundColor = backgroundColor
        view.addSubview(segmentedControlWrapperView)

        segmentedControl = UISegmentedControl(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        for (index, scope) in scopeStrings.enumerated() {
            segmentedControl.insertSegment(withTitle: scope, at: index, animated: false)
        }
        segmentedControl.selectedSegmentIndex = 0

        segmentedControl.tintColor = UIColor(red: 0.92, green: 0.67, blue: 0.01, alpha: 1.00)
        segmentedControl.addTarget(self, action: #selector(segmentedControlDidChange(_:)), for: .valueChanged)

        segmentedControlWrapperView.addSubview(segmentedControl)

        edgesForExtendedLayout = [.bottom, .left, .right]
    }

    // Add search for iOS10
    func setupSearchbariOS10() {
        searchWrapperView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)) // will get set in autolayout
        searchWrapperView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchWrapperView)

        let searchBar = searchController.searchBar
        searchController.searchBar.barTintColor = backgroundColor
        searchController.searchBar.backgroundColor = backgroundColor
        searchController.searchBar.isTranslucent = false

        searchWrapperView.addSubview(searchBar)

        edgesForExtendedLayout = [.bottom, .left, .right]
    }

    @objc func segmentedControlDidChange(_ sender: UISegmentedControl) {
        segmentedControlDelegate?.segmentedControlDidChange?(index: sender.selectedSegmentIndex, nil)
    }

    public func setupSearchBar() {
        // TODO: check if search bar should be added
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchBar.delegate = self
        searchController.hidesNavigationBarDuringPresentation = false
        searchController.dimsBackgroundDuringPresentation = false
        searchController.searchBar.sizeToFit()
        searchController.delegate = self

        if #available(iOS 11, *) {
            navigationItem.searchController = searchController
            // Default behaviour is searchbar is hidden until you pull down, so persist it
            navigationItem.hidesSearchBarWhenScrolling = false
        } else {
            setupSearchbariOS10()
        }

        definesPresentationContext = true

        if let textField = self.searchController.searchBar.value(forKey: "_searchField") as? UITextField {
            textField.clearButtonMode = .always
        }
    }

    func setupRefreshControl() {
        refreshControl.layer.zPosition = -1 // hide behind tableview cells
        refreshControl.attributedTitle = NSAttributedString(string: pullToRefreshText, attributes: [:])
        refreshControl.addTarget(self, action: #selector(refreshControlChanged), for: .valueChanged)

        tableView.addSubview(refreshControl)

        // this is important for getting the layout right, otherwise the refresh controls text can get cut off
        extendedLayoutIncludesOpaqueBars = true

        //        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        //            self.manuallyShowRefreshControl()
        //        }
    }

    func manuallyShowRefreshControl() {
        // Use this before any data is loaded to show an activity indicator to the user
        DispatchQueue.main.async {
            self.refreshControl.beginRefreshing()

            let yOffsetTable = self.tableView.contentOffset.y
            if yOffsetTable < CGFloat(Float.ulpOfOne) {
                UIView.animate(withDuration: 0.25,
                               delay: 0,
                               options: UIView.AnimationOptions.beginFromCurrentState,
                               animations: {
                                   self.refreshControl.attributedTitle = NSAttributedString(string: self.refreshingDataText,
                                                                                            attributes: [:])
                                   let refreshControlHeight = self.refreshControl.frame.height
                                   self.tableView.contentOffset = CGPoint(x: 0, y: -refreshControlHeight * 4)

                               },
                               completion: nil)
            }
        }
    }

    // TODO: not really sure if this needs to be public
    public func setNoContentLabel() {
        var noDataText = "No data"
        var noResults = false

        guard !isLoadingData else {
            setNoContentLabel(isHidden: false, text: refreshingDataText)
            return
        }

        if searchController.searchBar.text == "" && data?.count == 0 {
            noDataText = delegate?.textForNoData() ?? "No data"
            noResults = true
        } else if data?.count == 0 {
            noDataText = delegate?.textForNoData() ?? "No data"
            if let searchText = searchController.searchBar.text {
                noDataText += " matching the search term \"\(searchText)\""
            }
            noResults = true
        }

        let isHidden = !noResults || isLoadingData

        if noResults {
            setNoContentLabel(isHidden: isHidden, text: noDataText)
        }
    }

    public func setNoContentLabel(isHidden: Bool, text: String?, delay _: Bool = false) {
        if !isHidden {
            let tableViewSize = tableView.bounds.size
            let labelFrame = CGRect(x: 0, y: 0, width: tableViewSize.width - 32, height: tableViewSize.height)
            let noDataLabel = UILabel(frame: labelFrame)
            noDataLabel.text = text
            noDataLabel.textColor = UIColor.darkGray
            noDataLabel.textAlignment = NSTextAlignment.center
            noDataLabel.numberOfLines = 0

            tableView.backgroundView = noDataLabel
        } else {
            DispatchQueue.main.async {
                self.tableView.backgroundView = nil
            }
        }
    }

    func setInitialLoadingLabel() {
//        let tableViewSize = tableView.bounds.size
//        let labelFrame = CGRect(x: 0, y: 0, width: tableViewSize.width - 32, height: tableViewSize.height)
//        let noDataLabel = UILabel(frame: labelFrame)
//        noDataLabel.text = "\(refreshingDataText)..."
//        noDataLabel.textColor = UIColor.darkGray
//        noDataLabel.textAlignment = NSTextAlignment.center
//        noDataLabel.numberOfLines = 0
//
//        DispatchQueue.main.async {
//            self.tableView.backgroundView = noDataLabel
//        }

        setNoContentLabel()
    }

    // MARK: - Pull to refresh

    @objc func refreshControlChanged() {
        if !tableView.isDragging {
            refreshData()
        } else {
            let releaseToRefreshText = NSAttributedString(string: self.releaseToRefreshText, attributes: [:])
            refreshControl.attributedTitle = releaseToRefreshText
        }
    }

    open func scrollViewDidEndDragging(_: UIScrollView, willDecelerate _: Bool) {
        if refreshControl.isRefreshing {
            refreshData()
        }
    }

    // Happens when view loads for the first time or the user drags down to refresh
    public func refreshData() {
        setNoContentLabel()

        refreshControl.layoutIfNeeded()
        refreshControl.beginRefreshing()

        let refreshingAttributedTitle = NSAttributedString(string: refreshingDataText, attributes: [:])
        refreshControl.attributedTitle = refreshingAttributedTitle

        noMoreResults = false

        setNoContentLabel()

        isLoadingData = true
        if paginationIsEnabled {
            isLoadingData = true
            setNoContentLabel(isHidden: false, text: refreshingDataText)
            delegate?.loadPaginatedData?(page: 1, limit: itemsPerPage, query: searchTerms) {
                self.isLoadingData = false
                DispatchQueue.main.async {
                    self.setNoContentLabel()
                    self.loadingDataEnded()
                }
            }
        } else {
            // Load all the data
            delegate?.loadData?({
                self.loadingDataEnded()
            })
        }

        guard hasLoadedInitialData else {
            setInitialLoadingLabel()
            return
        }
    }

    func loadingDataEnded() {
        isLoadingData = false
        let pullToRefreshAttributedTitle = NSAttributedString(string: pullToRefreshText,
                                                              attributes: [:])
        DispatchQueue.main.async {
            self.refreshControl.attributedTitle = pullToRefreshAttributedTitle
            self.refreshControl.endRefreshing()
            self.setNoContentLabel()
            self.tableView.reloadData()
        }
    }

    func filterAndSetData() {
        filteredData = data?.filter({ (item) -> Bool in
            item.matchesQuery(query: searchTerms)
        })
    }
}

extension TPTableViewController: UITableViewDataSource {
    public func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let data = self.data else { return 0 }
        guard let filteredData = self.filteredData else { return 0 }

        if !data.isEmpty {
            DispatchQueue.main.async {
                self.tableView.backgroundView = nil
            }
        }

        if paginationIsEnabled, delegate?.filterDataForSection == nil {
            return self.data?.count ?? 0
        } else if paginationIsEnabled, delegate?.filterDataForSection != nil {
            return delegate?.filterDataForSection?(data: data,
                                                   section: section).count ?? 0
        } else {
            if delegate?.filterDataForSection != nil {
                return delegate?.filterDataForSection?(data: filteredData,
                                                       section: section).count ?? 0
            }

            return self.filteredData?.count ?? 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var item: TPTableData

        guard let data = data else { return UITableViewCell() }
        guard let filteredData = filteredData else { return UITableViewCell() }

        if paginationIsEnabled, delegate?.filterDataForSection == nil {
            item = data[indexPath.row]
        } else if paginationIsEnabled, delegate?.filterDataForSection != nil {
            if delegate?.filterDataForSection != nil {
                if let unwrappedItem = self.delegate?.filterDataForSection?(data: data,
                                                                            section: indexPath.section)[indexPath.row] {
                    item = unwrappedItem
                } else {
                    // error
                    return UITableViewCell()
                }
            } else {
                item = data[indexPath.row]
            }
        } else {
            if delegate?.filterDataForSection != nil {
                if let unwrappedItem = self.delegate?.filterDataForSection?(data: filteredData,
                                                                            section: indexPath.section)[indexPath.row] {
                    item = unwrappedItem
                } else {
                    // error
                    return UITableViewCell()
                }
            } else {
                item = filteredData[indexPath.row]
            }
        }

        return dataSource?.cellForRowAt(tableView: tableView,
                                        indexPath: indexPath,
                                        item: item) ?? UITableViewCell()
    }

    public func tableView(_ tableView: UITableView, willDisplay _: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let data = data else { return }

        if delegate?.filterDataForSection != nil {
            let lastSectionIndex = tableView.numberOfSections - 1

            guard lastSectionIndex == indexPath.section else {
                return
            }

            guard let lastSectionData = self.delegate?.filterDataForSection?(data: data,
                                                                             section: indexPath.section) else {
                return
            }

            if indexPath.row == lastSectionData.count - 1 {
                loadNextPage()
            }
        } else if paginationIsEnabled {
            // Check if we're displaying the last item. If we are, attempt to fetch the
            // next page of results

            let lastItem = data.count - 1
            if indexPath.row == lastItem {
                // Request more data
                loadNextPage()
            }
        }
    }
}

extension TPTableViewController: UITableViewDelegate {
    public func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        delegate?.didSelectRowAt(indexPath)
    }
}

extension TPTableViewController: UISearchBarDelegate {
    public func searchBar(_: UISearchBar, textDidChange searchText: String) {
        guard let data = data else { return }

        if paginationIsEnabled {
            isLoadingData = true
            noMoreResults = false
            setNoContentLabel(isHidden: false, text: refreshingDataText)
            delegate?.loadPaginatedData?(page: 1, limit: itemsPerPage, query: searchText, {
                self.isLoadingData = false
                DispatchQueue.main.async {
                    self.setNoContentLabel()
                }
            })

            searchTerms = searchText
        } else {
            filteredData = data.filter({ (item) -> Bool in
                item.matchesQuery(query: searchText)
            })
        }
    }

    open func searchBarTextDidBeginEditing(_: UISearchBar) {
        searchWasCancelled = false
    }

    open func searchBarCancelButtonClicked(_: UISearchBar) {
        searchWasCancelled = true

        noMoreResults = false
        guard searchTerms != "" else {
            // don't need to search again
            return
        }

        isLoadingData = true

        DispatchQueue.main.async {
            self.searchController.searchBar.text = ""
        }

        searchTerms = ""

        if paginationIsEnabled {
            DispatchQueue.main.async {
                self.setNoContentLabel(isHidden: false, text: self.refreshingDataText)
            }
            isLoadingData = true
            delegate?.loadPaginatedData?(page: 1, limit: itemsPerPage, query: "", {
                self.isLoadingData = false
                DispatchQueue.main.async {
                    self.setNoContentLabel()
                }
                self.isLoadingData = false
            })
        } else {
            DispatchQueue.main.async {
                self.filteredData = self.data
                self.tableView.reloadData()
            }
        }
    }

    open func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        if searchWasCancelled {
            searchBar.text = searchTerms
            if !paginationIsEnabled {
                filteredData = data
                tableView.reloadData()
            }
        } else {
            searchTerms = searchBar.text ?? ""
        }
    }
}

extension TPTableViewController: UISearchControllerDelegate {
    open func searchBar(_: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        isLoadingData = true
        filterDelegate?.didChangeScope?(scopeIndex: selectedScope, {
            self.isLoadingData = false
        })
    }
}

@objc public protocol TPTableViewDelegate: class {
    func didSelectRowAt(_ indexPath: IndexPath)
    func textForNoData() -> String
    @objc optional func loadData(_ completion: (() -> Void)!)
    @objc optional func loadData(query: String?, _ completion: (() -> Void)!)
    @objc optional func loadPaginatedData(page: Int, limit: Int, query: String, _ completion: (() -> Void)!)
    @objc optional func itemName() -> String
    @objc optional func filterDataForSection(data: [TPTableData], section: Int) -> [TPTableData]
    @objc func registerReusableCell()
}

public protocol TPTableViewDataSource: class {
    func cellForRowAt(tableView: UITableView, indexPath: IndexPath, item: TPTableData) -> UITableViewCell
}

@objc public protocol TPTableViewFilterDelegate: class {
    @objc optional func didChangeScope(scopeIndex: Int, _ completion: (() -> Void)!)
}

@objc public protocol TPTableViewSegmentedControlDelegate: class {
    @objc optional func segmentedControlDidChange(index: Int, _ completion: (() -> Void)!)
}

extension UISearchBar {
    private var textField: UITextField? {
        return subviews.first?.subviews.compactMap { $0 as? UITextField }.first
    }

    private var activityIndicator: UIActivityIndicatorView? {
        return textField?.leftView?.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
    }

    private var searchIcon: UIImage? {
        let subViews = subviews.flatMap { $0.subviews }
        return ((subViews.filter { $0 is UIImageView }).first as? UIImageView)?.image
    }

    var isLoading: Bool {
        get {
            return activityIndicator != nil
        } set {}

        //        get {
        //            return self.activityIndicator != nil
        //        } set {
        //            DispatchQueue.main.async {
        //
        //                let _searchIcon = self.searchIcon
        //
        //                if newValue {
        //                    if self.activityIndicator == nil {
        //                        let activityIndicator = UIActivityIndicatorView(style: .gray)
        //                        activityIndicator.startAnimating()
        //                        activityIndicator.backgroundColor = UIColor.clear
        //                        self.setImage(UIImage(), for: .search, state: .normal)
        //                        self.textField?.leftView?.addSubview(activityIndicator)
        //                        let leftViewSize = self.textField?.leftView?.frame.size ?? CGSize.zero
        //                        activityIndicator.center = CGPoint(x: leftViewSize.width/2, y: leftViewSize.height/2)
        //                    }
        //                } else {
        //                    self.setImage(_searchIcon, for: .search, state: .normal)
        //                    self.activityIndicator?.removeFromSuperview()
        //                }
        //            }
        //        }
    }
}

extension UIViewController {
    /// Calculate top distance with "navigationBar" and "statusBar" by adding a
    /// subview constraint to navigationBar or to topAnchor or superview
    /// - Returns: The real distance between topViewController and Bottom navigationBar
    func calculateTopDistance() -> CGFloat {
        /// Create view for misure
        let misureView: UIView = UIView()
        misureView.backgroundColor = .clear
        view.addSubview(misureView)

        /// Add needed constraint
        misureView.translatesAutoresizingMaskIntoConstraints = false
        misureView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        misureView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        misureView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        if let nav = navigationController {
            misureView.topAnchor.constraint(equalTo: nav.navigationBar.bottomAnchor).isActive = true
        } else {
            misureView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }

        /// Force layout
        view.layoutIfNeeded()

        /// Calculate distance
        let distance = view.frame.size.height - misureView.frame.size.height

        /// Remove from superview
        misureView.removeFromSuperview()

        return distance
    }
}
