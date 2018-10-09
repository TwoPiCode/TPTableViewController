//
//  TPTableViewController.swift
//  TPTableViewController
//

// TODO: list
// - Reduce drag distance for pull to refresh
// - Spinner background color - maybe it should be on the right so it doesn't obscure the search,
//   but also make sure not to obscure the clear button

import UIKit

class TPTableViewController: UIViewController {

    var tableView = UITableView()

    var data = [TPTableData]() {
        didSet {
            DispatchQueue.main.async {
                self.setNoContentLabel()
                self.tableView.reloadData()
            }
        }
    }

    // search bar
    var searchTerms = ""
    var searchWasCancelled = false

    // pagination
    var previousQuery = ""
    var noMoreResults = false
    let itemsPerPage = 10
    var pagesLoaded: Int {
        return Int(self.data.count / self.itemsPerPage)
    }

    weak var delegate: TPTableViewDelegate? {
        didSet {

        }
    }

    var releaseToRefreshText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName!() {
            return text
        } else {
            return "Release to refresh data"
        }
    }

    var pullToRefreshText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName!() {
            return text
        } else {
            return "Pull to refresh data"
        }
    }

    var refreshingDataText: String {
        if self.delegate?.itemName != nil, let text = delegate?.itemName!() {
            return text
        } else {
            return "Loading data"
        }
    }

    // Set to true when the API is loading data
    var isLoadingData: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.searchController.searchBar.isLoading = self.isLoadingData
            }
        }
    }
    var isFetchingData = false

    weak var dataSource: TPTableViewDataSource?

    private var refreshControl = UIRefreshControl()
    var searchController = UISearchController()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Data"
    }

    var hasSetupTable = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if !self.hasSetupTable {
            self.hasSetupTable = true

            self.setupTableView()
            self.setupSearchBar()
            self.setupRefreshControl()
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

        self.tableView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        self.tableView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        self.tableView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        self.tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true

        self.tableView.allowsSelection = self.delegate?.didSelectRowAt != nil
    }

    func setupSearchBar() {
        // TODO: check if search bar should be added
        self.searchController = UISearchController(searchResultsController: nil)
        self.searchController.searchBar.delegate = self
        navigationItem.searchController = searchController
        if let textField = self.searchController.searchBar.value(forKey: "_searchField") as? UITextField {
            textField.clearButtonMode = .always
        }

        self.searchController.dimsBackgroundDuringPresentation = false
//        searchController.obscuresBackgroundDuringPresentation = false

        // Default behaviour is searchbar is hidden until you pull down, so persist it
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationController?.navigationBar.prefersLargeTitles = false

        definesPresentationContext = true
    }

    func setupRefreshControl() {
        self.refreshControl.layer.zPosition = -1 // hide behind tableview cells
        self.refreshControl.attributedTitle = NSAttributedString(string: self.pullToRefreshText, attributes: [:])
        self.refreshControl.addTarget(self, action: #selector(self.refreshControlChanged), for: .valueChanged)

        self.tableView.addSubview(self.refreshControl)

        // this is important for getting the layout right, otherwise the refresh controls text can get cut off
        self.extendedLayoutIncludesOpaqueBars = true

        self.manuallyShowRefreshControl()
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

    func setNoContentLabel() {
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

    @objc func refreshControlChanged() {
        if !self.tableView.isDragging {
            self.refreshData()
        } else {
            let releaseToRefreshText = NSAttributedString(string: self.releaseToRefreshText, attributes: [:])
            self.refreshControl.attributedTitle = releaseToRefreshText
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if self.refreshControl.isRefreshing {
            self.refreshData()
        }
    }

    @objc func refreshData() {
        self.setNoContentLabel()
        self.isFetchingData = true
        self.refreshControl.layoutIfNeeded()
        self.refreshControl.beginRefreshing()

        let refreshingAttributedTitle = NSAttributedString(string: self.refreshingDataText, attributes: [:])
        refreshControl.attributedTitle = refreshingAttributedTitle

        noMoreResults = false

        self.delegate?.loadPaginatedData?(page: 1, limit: itemsPerPage, query: searchTerms) {
            DispatchQueue.main.async {
                self.isFetchingData = false
                let pullToRefreshAttributedTitle = NSAttributedString(string: self.pullToRefreshText,
                                                                      attributes: [:])
                self.refreshControl.attributedTitle = pullToRefreshAttributedTitle
                self.refreshControl.endRefreshing()
                self.tableView.reloadData()
            }
        }
    }
}

extension TPTableViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.setNoContentLabel()

        return self.data.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = data[indexPath.row]
        return self.dataSource?.cellForRowAt(tableView: tableView,
                                             indexPath: indexPath,
                                             item: item) ?? UITableViewCell()
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Check if we're displaying the last item. If we are, attempt to fetch the
        // next page of results

        let lastItem = data.count - 1
        if indexPath.row == lastItem {
            // Request more data
            self.loadNextPage()
        }
    }
}

extension TPTableViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        self.delegate?.didSelectRowAt(indexPath)
    }
}

extension TPTableViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.isLoadingData = true
        self.noMoreResults = false
        self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: searchText, {
            self.isLoadingData = false
        })

        self.searchTerms = searchText

        print("searching for \(searchText)")

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

    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool {
        // hmm
        return true
    }

    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        self.searchWasCancelled = false
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        self.searchWasCancelled = true

        self.noMoreResults = false
        guard searchTerms != "" else {
            // don't need to search again
            return

        }

        self.isLoadingData = true

        DispatchQueue.main.async {
            self.searchController.searchBar.text = ""
        }

        searchTerms = ""


        self.delegate?.loadPaginatedData?(page: 1, limit: self.itemsPerPage, query: "", {
            self.isLoadingData = false
        })
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        if self.searchWasCancelled {
            searchBar.text = self.searchTerms
        } else {
            self.searchTerms = searchBar.text ?? ""
        }
    }

}

@objc protocol TPTableViewDelegate: class {
    func didSelectRowAt(_ indexPath: IndexPath)
    func textForNoData() -> String
    @objc optional func loadData(query: String?, _ completion: (() -> Void)!)
    @objc optional func loadPaginatedData(page: Int, limit: Int, query: String, _ completion: (() -> Void)!)
    @objc optional func itemName() -> String
}

protocol TPTableViewDataSource: class {
    func cellForRowAt(tableView: UITableView, indexPath: IndexPath, item: TPTableData) -> UITableViewCell
}

extension UISearchBar {

    private var textField: UITextField? {
        return subviews.first?.subviews.compactMap { $0 as? UITextField }.first
    }

    private var activityIndicator: UIActivityIndicatorView? {
        return self.textField?.leftView?.subviews.compactMap { $0 as? UIActivityIndicatorView }.first
    }

    var isLoading: Bool {
        get {
            return self.activityIndicator != nil
        } set {
            DispatchQueue.main.async {

                if newValue {
                    if self.activityIndicator == nil {
                        let newActivityIndicator = UIActivityIndicatorView(style: .gray)
                        newActivityIndicator.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                        newActivityIndicator.startAnimating()
                        newActivityIndicator.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.00)
                        self.textField?.leftView?.addSubview(newActivityIndicator)
                        let leftViewSize = self.textField?.leftView?.frame.size ?? CGSize.zero
                        newActivityIndicator.center = CGPoint(x: leftViewSize.width / 2, y: leftViewSize.height / 2)
                    }
                } else {
                    self.activityIndicator?.removeFromSuperview()
                }
            }
        }
    }
}
