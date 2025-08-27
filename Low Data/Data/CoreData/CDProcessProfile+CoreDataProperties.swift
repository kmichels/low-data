//
//  CDProcessProfile+CoreDataProperties.swift
//  Low Data
//
//  Created by Konrad Michels on 8/27/25.
//

import Foundation
import CoreData

extension CDProcessProfile {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDProcessProfile> {
        return NSFetchRequest<CDProcessProfile>(entityName: "CDProcessProfile")
    }
    
    @NSManaged public var processIdentifier: String?
    @NSManaged public var processName: String?
    @NSManaged public var processType: String?
    @NSManaged public var bundleId: String?
    @NSManaged public var path: String?
    @NSManaged public var observationCount: Int32
    @NSManaged public var averageBandwidth: Double
    @NSManaged public var peakBandwidth: Double
    @NSManaged public var totalBytesIn: Int64
    @NSManaged public var totalBytesOut: Int64
    @NSManaged public var lastSeen: Date?
    @NSManaged public var isBursty: Bool
}

extension CDProcessProfile: Identifiable {
    public var id: String? { processIdentifier }
}