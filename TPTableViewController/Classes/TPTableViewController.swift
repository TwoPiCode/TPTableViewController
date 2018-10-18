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
    public var segmentedControl = UISegmentedControl()

    public var data = [TPTableData]() {
        didSet {
            DispatchQueue.main.async {
                if !self.paginationIsEnabled {
                    self.filterAndSetData()
                }

                self.setNoContentLabel()
                self.tableView.reloadData()
            }
        }
    }

    public var filteredData = [TPTableData]() {
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
    var segmentedControlEnabled = true


    // search bar
    public var searchTerms = ""
    public var searchWasCancelled = false

    // pagination
    public var paginationIsEnabled = false
    var previousQuery = ""
    public var noMoreResults = false
    public let itemsPerPage = 20
    var pagesLoaded: Int {
        return Int(self.data.count / self.itemsPerPage)
    }

    open weak var delegate: TPTableViewDelegate? {
        didSet {

        }
    }

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
            return "Loading \(text.lowercased())"
        } else {
            return "Loading data"
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

    open override func viewDidLoad() {
        super.viewDidLoad()

        if let itemName = delegate?.itemName?() {
            title = itemName
        }
    }

    var hasSetupTable = false

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !self.hasSetupTable {
            self.hasSetupTable = true

            self.setupTableView()
            self.setupSearchBar()
            self.setupRefreshControl()
            self.refreshData()
        }
    }

    func setupTableView() {
        // Setup tableview
        self.tableView.dataSource = self
        self.tableView.delegate = self
        self.tableView.backgroundColor = UIColor.groupTableViewBackground
        self.tableView.keyboardDismissMode = .onDrag

        let footerFrame = CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 1)
        self.tableView.tableFooterView = UIView(frame: footerFrame)

        // Start: Add tableview, add constraints
        view.addSubview(self.tableView)

        self.tableView.translatesAutoresizingMaskIntoConstraints = false

        if segmentedControlEnabled {
            segmentedControl = UISegmentedControl(items: ["One", "Two"])
            view.addSubview(segmentedControl)
            //            segmentedControl.insertSegment(withTitle: "One", at: 0, animated: true)
            //            segmentedControl.insertSegment(withTitle: "Two", at: 1, animated: true)
            //            segmentedControl.setTitle("One", forSegmentAt: 0)
            //            segmentedControl.setTitle("Two", forSegmentAt: 1)

            segmentedControl.translatesAutoresizingMaskIntoConstraints = false

            if #available(iOS 11.0, *) {
                segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
            } else {
                segmentedControl.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            }
            segmentedControl.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            segmentedControl.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
            self.tableView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor).isActive = true
        } else {
            self.tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        }

        self.tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        self.tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        self.tableView.allowsSelection = self.delegate?.didSelectRowAt != nil
    }

    public func setupSearchBar() {
        // TODO: check if search bar should be added
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.searchBar.delegate = self

        if #available(iOS 11, *) {
            navigationItem.searchController = searchController
            navigationItem.largeTitleDisplayMode = .never
        }

        if let textField = self.searchController.searchBar.value(forKey: "_searchField") as? UITextField {
            textField.clearButtonMode = .always
        }

        self.searchController.dimsBackgroundDuringPresentation = false

        // Default behaviour is searchbar is hidden until you pull down, so persist it
        if #available(iOS 11, *) {
            navigationItem.hidesSearchBarWhenScrolling = false
        }

        definesPresentationContext = true

        // scopes
        //        self.searchController.searchBar.scopeButtonTitles = scopes
        //        self.searchController.searchBar.showsScopeBar = true

        self.searchController.searchBar.sizeToFit()
        self.searchController.delegate = self
    }

    func setupRefreshControl() {
        self.refreshControl.layer.zPosition = -1 // hide behind tableview cells
        self.refreshControl.attributedTitle = NSAttributedString(string: self.pullToRefreshText, attributes: [:])
        self.refreshControl.addTarget(self, action: #selector(self.refreshControlChanged), for: .valueChanged)

        self.tableView.addSubview(self.refreshControl)

        // this is important for getting the layout right, otherwise the refresh controls text can get cut off
        self.extendedLayoutIncludesOpaqueBars = true

        //        self.manuallyShowRefreshControl()
    }

    func manuallyShowRefreshControl() {
        // Use this before any data is loaded to show an activity indicator to the user
        DispatchQueue.main.async {
            self.refreshControl.beginRefreshing()

            let yOffsetTable = self.tableView.contentOffset.y
            if yOffsetTable < CGFloat(Float.ulpOfOne) {
                UIView.animate(withDuration: 0.25, delay: 0, options: UIView.AnimationOptions.beginFromCurrentState, animations: {
                    self.refreshControl.attributedTitle = NSAttributedString(string: self.refreshingDataText, attributes: [:])
                    let refreshControlHeight = self.refreshControl.frame.height
                    self.tableView.contentOffset = CGPoint(x: 0, y: -refreshControlHeight * 4)

                }, completion: nil)
            }
        }
    }

    // TODO: not really sure if this needs to be public
    public func setNoContentLabel() {
        var noDataText = "No data"
        var noResults = false

        if self.searchController.searchBar.text == "" && self.data.count == 0 {
            noDataText = self.delegate?.textForNoData() ?? "No data"
            noResults = true
        } else if self.data.count == 0 {
            noDataText = self.delegate?.textForNoData() ?? "No data"
            if let searchText = searchController.searchBar.text {
                noDataText += " matching the search term \"\(searchText)\""
            }
            noResults = true
        }
        //        else if self.filteredData.count == 0 {
        //            if let searchText = searchController?.searchBar.text {
        //                let defaultText = "\("No data") found matching the search term \"\(searchText)\""
        //                noDataText = self.delegate?.textForNoData() ?? defaultText
        //                noResults = true
        //            }
        //        }

        let isHidden = !noResults || isFetchingData

        setNoContentLabel(isHidden: isHidden, text: noDataText)
    }

    func setNoContentLabel(isHidden: Bool, text: String?) {
        if !isHidden {
            let tableViewSize = tableView.bounds.size
            let labelFrame = CGRect(x: 0, y: 0, width: tableViewSize.width - 32, height: tableViewSize.height)
            let noDataLabel = UILabel(frame: labelFrame)
            noDataLabel.text = text
            noDataLabel.textColor = UIColor.darkGray
            noDataLabel.textAlignment = NSTextAlignment.center
            noDataLabel.numberOfLines = 0

            DispatchQueue.main.async {
                self.tableView.backgroundView = noDataLabel
            }
        } else {
            DispatchQueue.main.async {
                self.tableView.backgroundView = nil
            }
        }
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
        self.setNoContentLabel()
        self.isFetchingData = true
        self.refreshControl.layoutIfNeeded()
        self.refreshControl.beginRefreshing()

        let refreshingAttributedTitle = NSAttributedString(string: self.refreshingDataText, attributes: [:])
        refreshControl.attributedTitle = refreshingAttributedTitle

        noMoreResults = false

        if self.paginationIsEnabled {
            self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: self.searchTerms) {
                DispatchQueue.main.async {
                    self.loadingDataEnded()
                }
            }
        } else {
            // Load all the data
            self.delegate?.loadData?({
                self.loadingDataEnded()
            })
        }
    }

    func loadingDataEnded() {
        self.isFetchingData = false
        let pullToRefreshAttributedTitle = NSAttributedString(string: self.pullToRefreshText,
                                                              attributes: [:])
        DispatchQueue.main.async {
            self.refreshControl.attributedTitle = pullToRefreshAttributedTitle
            self.refreshControl.endRefreshing()
            self.tableView.reloadData()
        }
    }

    func filterAndSetData() {
        self.filteredData = self.data.filter({ (item) -> Bool in
            item.matchesQuery(query: searchTerms)
        })
    }
}

extension TPTableViewController: UITableViewDataSource {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.setNoContentLabel()

        if self.paginationIsEnabled {
            return self.data.count
        } else {
            return self.filteredData.count
        }
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var item: TPTableData

        if self.paginationIsEnabled {
            item = self.data[indexPath.row]
        } else {
            item = self.filteredData[indexPath.row]
        }

        return self.dataSource?.cellForRowAt(tableView: tableView,
                                             indexPath: indexPath,
                                             item: item) ?? UITableViewCell()
    }

    public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {

        if self.paginationIsEnabled {
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
        tableView.deselectRow(at: indexPath, animated: true)
        self.delegate?.didSelectRowAt(indexPath)
    }
}

extension TPTableViewController: UISearchBarDelegate {
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {

        if self.paginationIsEnabled {
            self.isLoadingData = true
            self.noMoreResults = false
            self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: searchText, {
                self.isLoadingData = false
            })

            self.searchTerms = searchText
        } else {
            self.filteredData = self.data.filter({ (item) -> Bool in
                item.matchesQuery(query: searchText)
            })
        }

        //        if paginationIsEnabled {
        //            self.filterData(searchText: searchText)
        //        } else {
        //            // with filtering
        //            // self.filterData(searchText: searchText)
        //
        //            // without filtering
        //            // filter the data for the search and then reload
        //            self.filteredData = self.data.filter({ (item) -> Bool in
        //                item.matchesQuery(query: searchText)
        //            })
        //
        //            self.tableView.reloadData()
        //        }
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

        self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: "", {
            self.isLoadingData = false
        })
    }

    open func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        if self.searchWasCancelled {
            searchBar.text = self.searchTerms
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
}

public protocol TPTableViewDataSource: class {
    func cellForRowAt(tableView: UITableView, indexPath: IndexPath, item: TPTableData) -> UITableViewCell
}

@objc public protocol TPTableViewFilterDelegate: class {
    @objc optional func didChangeScope(scopeIndex: Int, _ completion: (() -> Void)!)
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

extension UIViewController{


    /// Calculate top distance with "navigationBar" and "statusBar" by adding a
    /// subview constraint to navigationBar or to topAnchor or superview
    /// - Returns: The real distance between topViewController and Bottom navigationBar
    func calculateTopDistance() -> CGFloat{

        /// Create view for misure
        let misureView : UIView     = UIView()
        misureView.backgroundColor  = .clear
        view.addSubview(misureView)

        /// Add needed constraint
        misureView.translatesAutoresizingMaskIntoConstraints                    = false
        misureView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive     = true
        misureView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive   = true
        misureView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        if let nav = navigationController {
            misureView.topAnchor.constraint(equalTo: nav.navigationBar.bottomAnchor).isActive = true
        }else{
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
