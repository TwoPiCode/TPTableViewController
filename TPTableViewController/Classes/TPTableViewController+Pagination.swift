//
//  TPTableViewController+Pagination.swift
//  TPTableViewController
//

import Foundation
import UIKit

extension TPTableViewController {
    func loadNextPage() {
        var page = 1
        let query = searchController.searchBar.text ?? ""

        if self.previousQuery == query {
            // if the search query hasn't changed, we want to load the next page of results
            guard !noMoreResults else {
                // there are no more results to fetch

                return
            }
            page = self.pagesLoaded + 1
        } else {
            // otherwise don't prevent the API from loading more results
            self.noMoreResults = false
        }

        // show an activity indicator in the table footer
        let spinner = UIActivityIndicatorView(style: .gray)
        spinner.startAnimating()
        spinner.frame = CGRect(x: CGFloat(0), y: CGFloat(0), width: tableView.bounds.width, height: CGFloat(44))

        tableView.tableFooterView = spinner
        tableView.tableFooterView?.isHidden = false

        self.delegate?.loadPaginatedData?(page: page, limit: itemsPerPage, query: query, {

            DispatchQueue.main.async {
                let footerFrame = CGRect(x: 0, y: 0, width: self.tableView.frame.size.width, height: 1)
                self.tableView.tableFooterView = UIView(frame: footerFrame)
            }

            // Check that we haven't hit the last result
            if self.data.count != (page * self.itemsPerPage) {
                self.noMoreResults = true
            }

            self.previousQuery = query
        })
    }
}
