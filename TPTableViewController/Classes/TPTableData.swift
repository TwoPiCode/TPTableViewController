//
//  TPTableData.swift
//  TPTableViewController
//

import Foundation

class TPTableData: NSObject {
    var title: String?

    override init() {
        super.init()
    }

    init(title: String? = nil) {
        self.title = title
    }

    var titleForItem: String? {
        return self.title
    }

    func matchesQuery(query: String) -> Bool {
        return true
    }
}
