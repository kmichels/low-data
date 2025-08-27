//
//  CDTrafficObservation+CoreDataProperties.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData

extension CDTrafficObservation {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTrafficObservation> {
        return NSFetchRequest<CDTrafficObservation>(entityName: "CDTrafficObservation")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var processIdentifier: String?
    @NSManaged public var processName: String?
    @NSManaged public var processType: String?
    @NSManaged public var bytesIn: Int64
    @NSManaged public var bytesOut: Int64
    @NSManaged public var networkType: String?
    @NSManaged public var networkSSID: String?
    @NSManaged public var destinationHost: String?
    @NSManaged public var destinationPort: Int32
}

extension CDTrafficObservation: Identifiable {
    
}