//
//  IntentHandler.swift
//  AltStore
//
//  Created by Riley Testut on 7/6/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

#if !os(tvOS)
@preconcurrency import UIKit
import Foundation

final class IntentHandler: NSObject, RefreshAllIntentHandling
{
    private let queue = DispatchQueue(label: "io.sidestore.IntentHandler")
    
    private var completionHandlers = [RefreshAllIntent: (RefreshAllIntentResponse) -> Void]()
    private var queuedResponses = [RefreshAllIntent: RefreshAllIntentResponse]()
    
    private var operations = [RefreshAllIntent: BackgroundRefreshAppsOperation]()
    
    func confirm(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)
    {
        completion(RefreshAllIntentResponse.failure(localizedDescription: "请在定位助手的续签页手动刷新。"))
    }
    
    func handle(intent: RefreshAllIntent, completion: @escaping (RefreshAllIntentResponse) -> Void)
    {
        completion(RefreshAllIntentResponse.failure(localizedDescription: "请在定位助手的续签页手动刷新。"))
    }
}

private extension IntentHandler
{
    func finish(_ intent: RefreshAllIntent, response: RefreshAllIntentResponse)
    {
        self.queue.async {
            if let completionHandler = self.completionHandlers[intent]
            {
                self.completionHandlers[intent] = nil
                completionHandler(response)
            }
            else if response.code != .ready && response.code != .inProgress
            {
                // Queue response in case refreshing finishes after confirm() but before handle().
                self.queuedResponses[intent] = response
                DispatchQueue.main.async {
                    UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                }
            }
        }
    }
    
    func refreshApps(intent: RefreshAllIntent)
    {
        
        let context = DatabaseManager.shared.persistentContainer.newBackgroundContext()
        let installedApps = InstalledApp.fetchAppsForRefreshingAll(in: context)
        let operation = try? AppManager.shared.backgroundRefresh(installedApps, presentsNotifications: false) { (result) in
            do
            {
                let results = try result.get()
                
                for (_, result) in results
                {
                    guard case let .failure(error) = result else { continue }
                    throw error
                }
                
                self.finish(intent, response: RefreshAllIntentResponse(code: .success, userActivity: nil))
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            }
            catch OperationError.noInstalledApps
            {
                self.finish(intent, response: RefreshAllIntentResponse(code: .success, userActivity: nil))
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            }
            catch let error as NSError
            {
                debugLog("Failed to refresh apps in background. \(error)")
                self.finish(intent, response: RefreshAllIntentResponse.failure(localizedDescription: error.localizedFailureReason ?? error.localizedDescription))
            }
            
            self.operations[intent] = nil
        }
        
        self.operations[intent] = operation
    }
}
#endif
