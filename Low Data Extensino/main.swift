//
//  main.swift
//  Low Data Extension
//
//  Created by Konrad Michels on 8/27/25.
//

import NetworkExtension
import OSLog

/// Entry point for the System Extension
autoreleasepool {
    let logger = Logger(subsystem: "com.lowdata.extension", category: "Main")
    logger.info("Low Data System Extension starting...")
    
    NEProvider.startSystemExtensionMode()
}

// This call never returns
dispatchMain()