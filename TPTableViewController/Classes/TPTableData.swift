//
//  TPTableData.swift
//  TPTableViewController
//

import Foundation

open class TPTableData: NSObject {
    public override init() {
        super.init()
    }

    open func matchesQuery(query _: String) -> Bool {
        return true
    }
}
