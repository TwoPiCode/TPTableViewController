//
//  TPTableData.swift
//  TPTableViewController
//

import Foundation

open class TPTableData: NSObject {
    open var title: String?

    public override init() {
        super.init()
    }

    public init(title: String? = nil) {
        self.title = title
    }

    open var titleForItem: String? {
        return self.title
    }

    open func matchesQuery(query: String) -> Bool {
        return true
    }
}
