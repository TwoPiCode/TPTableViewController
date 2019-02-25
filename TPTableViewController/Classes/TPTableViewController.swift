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
                self.filteredData = self.data
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
                self.setNoContentLabel()
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
        return Int(self.data?.count ?? 0 / self.itemsPerPage)
    }

    public var deselectCellOnWillAppear = true

    var hasLoadedInitialData = false

    open weak var delegate: TPTableViewDelegate? {
        didSet {

        }
    }

    open weak var segmentedControlDelegate: TPTableViewSegmentedControlDelegate?

    var releaseToRefreshText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName?() {
            return "Release to refresh \(text.lowercased())"
        } else {
            return "Release to refresh data"
        }
    }

    var pullToRefreshText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName?() {
            return "Pull to refresh \(text.lowercased())"
        } else {
            return "Pull to refresh data"
        }
    }

    var refreshingDataText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName?() {
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
    public var isFetchingData = false

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

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        if let itemName = delegate?.itemName?() {
            title = itemName
        }

        self.setupSearchBar()
    }

    var hasSetupTable = false

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !self.hasSetupTable {
            self.hasSetupTable = true

            self.setupTableView()
            self.setupRefreshControl()

            self.layoutView()
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

        if !self.hasLoadedInitialData {
            self.refreshData()
        }

        //        }
    }

    func layoutView() {

        // these constraints are always needed
        self.tableView.translatesAutoresizingMaskIntoConstraints = false
        self.tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        self.tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        // if iOS <11 then we need to layout the searchbar
        if #available(iOS 11, *) {

        } else {
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
        if self.scopeStrings.count != 0 {
            self.segmentedControlWrapperView.translatesAutoresizingMaskIntoConstraints = false
            self.segmentedControl.translatesAutoresizingMaskIntoConstraints = false

            self.segmentedControlWrapperView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            self.segmentedControlWrapperView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true

            // If iOS >= 11 searchbar bottom is the same as topAnchor
            if #available(iOS 11, *) {
                segmentedControlWrapperView.topAnchor.constraint(equalTo: topLayoutGuide.topAnchor).isActive = true
            } else {
                self.segmentedControlWrapperView.topAnchor.constraint(equalTo: self.searchWrapperView.bottomAnchor).isActive = true
            }

            self.segmentedControl.centerXAnchor.constraint(equalTo: self.segmentedControlWrapperView.centerXAnchor).isActive = true
            self.segmentedControl.centerYAnchor.constraint(equalTo: self.segmentedControlWrapperView.centerYAnchor).isActive = true
            self.segmentedControl.topAnchor.constraint(equalTo: self.segmentedControlWrapperView.topAnchor, constant: 8).isActive = true
            self.segmentedControl.bottomAnchor.constraint(equalTo: self.segmentedControlWrapperView.bottomAnchor, constant: -8).isActive = true
            self.segmentedControl.leftAnchor.constraint(equalTo: self.segmentedControlWrapperView.leftAnchor, constant: 8).isActive = true
            self.segmentedControl.rightAnchor.constraint(equalTo: self.segmentedControlWrapperView.rightAnchor, constant: -8).isActive = true

            self.tableView.topAnchor.constraint(equalTo: self.segmentedControlWrapperView.bottomAnchor).isActive = true
        } else {
            // tableview top is searchbar bottom
            // If iOS >= 11 searchbar bottom is the same as topAnchor
            if #available(iOS 11, *) {
                tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            } else {
                self.tableView.topAnchor.constraint(equalTo: self.searchWrapperView.bottomAnchor).isActive = true
            }
        }
    }

    func setupTableView() {
        self.tableView = UITableView(frame: self.view.frame, style: self.style)

        self.delegate?.registerReusableCell()

        // Setup tableview
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = UIColor.groupTableViewBackground
        self.tableView.keyboardDismissMode = .onDrag

        self.tableView.rowHeight = UITableView.automaticDimension
        // It'd be a good idea to set this in the subclasses, and make sure this doesn't override it
        self.tableView.estimatedRowHeight = 44

        let footerFrame = CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 1)
        self.tableView.tableFooterView = UIView(frame: footerFrame)

        // Start: Add tableview, add constraints
        view.addSubview(self.tableView)

        if self.scopeStrings.count != 0 {
            self.setupSegmentedControl()
        }

        self.tableView.allowsSelection = self.delegate?.didSelectRowAt != nil
    }

    func setupSegmentedControl() {
        self.segmentedControlWrapperView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)) // will get set in autolayout

        self.segmentedControlWrapperView.backgroundColor = backgroundColor
        view.addSubview(self.segmentedControlWrapperView)

        self.segmentedControl = UISegmentedControl(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        for (index, scope) in self.scopeStrings.enumerated() {
            self.segmentedControl.insertSegment(withTitle: scope, at: index, animated: false)
        }
        self.segmentedControl.selectedSegmentIndex = 0

        self.segmentedControl.tintColor = UIColor(red: 0.92, green: 0.67, blue: 0.01, alpha: 1.00)
        self.segmentedControl.addTarget(self, action: #selector(self.segmentedControlDidChange(_:)), for: .valueChanged)

        self.segmentedControlWrapperView.addSubview(self.segmentedControl)

        edgesForExtendedLayout = [.bottom, .left, .right]
    }

    // Add search for iOS10
    func setupSearchbariOS10() {
        self.searchWrapperView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1)) // will get set in autolayout
        self.searchWrapperView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self.searchWrapperView)

        let searchBar = self.searchController.searchBar
        searchController.searchBar.barTintColor = backgroundColor
        searchController.searchBar.backgroundColor = backgroundColor
        searchController.searchBar.isTranslucent = false

        searchWrapperView.addSubview(searchBar)

        edgesForExtendedLayout = [.bottom, .left, .right]
    }

    @objc func segmentedControlDidChange(_ sender: UISegmentedControl) {
        self.segmentedControlDelegate?.segmentedControlDidChange?(index: sender.selectedSegmentIndex, nil)
    }

    public func setupSearchBar() {
        // TODO: check if search bar should be added
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.searchBar.delegate = self
        self.searchController.hidesNavigationBarDuringPresentation = false
        self.searchController.dimsBackgroundDuringPresentation = false
        self.searchController.searchBar.sizeToFit()
        self.searchController.delegate = self

        if #available(iOS 11, *) {
            navigationItem.searchController = searchController
            // Default behaviour is searchbar is hidden until you pull down, so persist it
            navigationItem.hidesSearchBarWhenScrolling = false
        } else {
            self.setupSearchbariOS10()
        }

        definesPresentationContext = true

        if let textField = self.searchController.searchBar.value(forKey: "_searchField") as? UITextField {
            textField.clearButtonMode = .always
        }
    }

    func setupRefreshControl() {
        self.refreshControl.layer.zPosition = -1 // hide behind tableview cells
        self.refreshControl.attributedTitle = NSAttributedString(string: self.pullToRefreshText, attributes: [:])
        self.refreshControl.addTarget(self, action: #selector(self.refreshControlChanged), for: .valueChanged)

        self.tableView.addSubview(self.refreshControl)

        // this is important for getting the layout right, otherwise the refresh controls text can get cut off
        self.extendedLayoutIncludesOpaqueBars = true

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

        if self.searchController.searchBar.text == "" && self.data?.count == 0 {
            noDataText = self.delegate?.textForNoData() ?? "No data"
            noResults = true
        } else if self.data?.count == 0 {
            noDataText = self.delegate?.textForNoData() ?? "No data"
            if let searchText = searchController.searchBar.text {
                noDataText += " matching the search term \"\(searchText)\""
            }
            noResults = true
        }

        let isHidden = !noResults || isFetchingData

        if noResults {
            self.setNoContentLabel(isHidden: isHidden, text: noDataText)
        }
    }

    public func setNoContentLabel(isHidden: Bool, text: String?, delay: Bool = false) {
        if !isHidden {
            let tableViewSize = tableView.bounds.size
            let labelFrame = CGRect(x: 0, y: 0, width: tableViewSize.width - 32, height: tableViewSize.height)
            let noDataLabel = UILabel(frame: labelFrame)
            noDataLabel.text = text
            noDataLabel.textColor = UIColor.darkGray
            noDataLabel.textAlignment = NSTextAlignment.center
            noDataLabel.numberOfLines = 0

            self.tableView.backgroundView = noDataLabel
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
        if !self.tableView.isDragging {
            self.refreshData()
        } else {
            let releaseToRefreshText = NSAttributedString(string: self.releaseToRefreshText, attributes: [:])
            self.refreshControl.attributedTitle = releaseToRefreshText
        }
    }

    open func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if self.refreshControl.isRefreshing {
            self.refreshData()
        }
    }

    // Happens when view loads for the first time or the user drags down to refresh
    public func refreshData() {
        self.isFetchingData = true
        self.setNoContentLabel()

        self.refreshControl.layoutIfNeeded()
        self.refreshControl.beginRefreshing()

        let refreshingAttributedTitle = NSAttributedString(string: self.refreshingDataText, attributes: [:])
        refreshControl.attributedTitle = refreshingAttributedTitle

        noMoreResults = false

        self.setNoContentLabel()

        if self.paginationIsEnabled {
            self.setNoContentLabel(isHidden: false, text: refreshingDataText)
            self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: self.searchTerms) {
                DispatchQueue.main.async {
                    self.setNoContentLabel()
                    self.loadingDataEnded()
                }
            }
        } else {
            // Load all the data
            self.delegate?.loadData?({
                self.loadingDataEnded()
            })
        }

        guard hasLoadedInitialData else {
            self.setInitialLoadingLabel()
            return
        }
    }

    func loadingDataEnded() {
        self.isFetchingData = false
        let pullToRefreshAttributedTitle = NSAttributedString(string: self.pullToRefreshText,
                                                              attributes: [:])
        DispatchQueue.main.async {
            self.refreshControl.attributedTitle = pullToRefreshAttributedTitle
            self.refreshControl.endRefreshing()
            self.setNoContentLabel()
            self.tableView.reloadData()
        }
    }

    func filterAndSetData() {
        self.filteredData = self.data?.filter({ (item) -> Bool in
            item.matchesQuery(query: searchTerms)
        })
    }
}

extension TPTableViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.setNoContentLabel()

        guard let data = self.data else { return 0 }
        guard let filteredData = self.filteredData else { return 0 }

        if self.paginationIsEnabled && self.delegate?.filterDataForSection == nil {
            return self.data?.count ?? 0
        } else if self.paginationIsEnabled && self.delegate?.filterDataForSection != nil {
            return self.delegate?.filterDataForSection?(data: data,
                                                        section: section).count ?? 0
        } else {
            if self.delegate?.filterDataForSection != nil {
                return self.delegate?.filterDataForSection?(data: filteredData,
                                                            section: section).count ?? 0
            }

            return self.filteredData?.count ?? 0
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var item: TPTableData

        guard let data = data else { return UITableViewCell() }
        guard let filteredData = filteredData else { return UITableViewCell() }

        if self.paginationIsEnabled && self.delegate?.filterDataForSection == nil {
            item = data[indexPath.row]
        } else if self.paginationIsEnabled && self.delegate?.filterDataForSection != nil {
            if self.delegate?.filterDataForSection != nil {
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

            if self.delegate?.filterDataForSection != nil {
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

        return self.dataSource?.cellForRowAt(tableView: tableView,
                                             indexPath: indexPath,
                                             item: item) ?? UITableViewCell()
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let data = data else { return }

        if self.delegate?.filterDataForSection != nil {
            let lastSectionIndex = tableView.numberOfSections - 1

            guard lastSectionIndex == indexPath.section else {
                return
            }

            guard let lastSectionData = self.delegate?.filterDataForSection?(data: data,
                                                                             section: indexPath.section) else {
                                                                                return
            }

            if indexPath.row == lastSectionData.count - 1 {
                self.loadNextPage()
            }
        } else if self.paginationIsEnabled {
            // Check if we're displaying the last item. If we are, attempt to fetch the
            // next page of results

            let lastItem = data.count - 1
            if indexPath.row == lastItem {
                // Request more data
                self.loadNextPage()
            }
        }
    }
}

extension TPTableViewController: UITableViewDelegate {
    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.delegate?.didSelectRowAt(indexPath)
    }
}

extension TPTableViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard let data = data else { return }

        if self.paginationIsEnabled {
            self.isLoadingData = true
            self.noMoreResults = false
            self.setNoContentLabel(isHidden: false, text: refreshingDataText)
            self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: searchText, {
                DispatchQueue.main.async {
                    self.setNoContentLabel()
                }
                self.isLoadingData = false
            })

            self.searchTerms = searchText
        } else {
            self.filteredData = data.filter({ (item) -> Bool in
                item.matchesQuery(query: searchText)
            })
        }
    }

    open func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.searchWasCancelled = false
    }

    open func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.searchWasCancelled = true

        self.noMoreResults = false
        guard self.searchTerms != "" else {
            // don't need to search again
            return
        }

        self.isLoadingData = true

        DispatchQueue.main.async {
            self.searchController.searchBar.text = ""
        }

        self.searchTerms = ""

        if self.paginationIsEnabled {
            DispatchQueue.main.async {
                self.setNoContentLabel(isHidden: false, text: self.refreshingDataText)
            }
            self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: "", {
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
        if self.searchWasCancelled {
            searchBar.text = self.searchTerms
            if !self.paginationIsEnabled {
                self.filteredData = self.data
                self.tableView.reloadData()
            }
        } else {
            self.searchTerms = searchBar.text ?? ""
        }
    }
}

extension TPTableViewController: UISearchControllerDelegate {
    open func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        self.isLoadingData = true
        self.filterDelegate?.didChangeScope?(scopeIndex: selectedScope, {
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
        return self.textField?.leftView?.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
    }

    private var searchIcon: UIImage? {
        let subViews = subviews.flatMap { $0.subviews }
        return ((subViews.filter { $0 is UIImageView }).first as? UIImageView)?.image
    }

    var isLoading: Bool {
        get {
            return self.activityIndicator != nil
        } set {

        }

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
