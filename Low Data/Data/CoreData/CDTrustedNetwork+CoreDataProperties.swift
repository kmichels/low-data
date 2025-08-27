//
//  CDTrustedNetwork+CoreDataProperties.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData

extension CDTrustedNetwork {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTrustedNetwork> {
        return NSFetchRequest<CDTrustedNetwork>(entityName: "CDTrustedNetwork")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var identifiersData: Data?
    @NSManaged public var dateAdded: Date?
    @NSManaged public var isEnabled: Bool
    @NSManaged public var customRulesData: Data?
}

extension CDTrustedNetwork: Identifiable {
    
}