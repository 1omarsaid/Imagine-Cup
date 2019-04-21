//
//  AppDelegate.swift
//  TinyYOLO-CoreML
//
//  Created by omar on 2019-02-16.
//  Copyright © 2019 MachineThink. All rights reserved.
//

import UIKit
import UserNotifications
import Alamofire
import CoreLocation



@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        completionHandler([.alert, .badge, .sound])
    }

    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        UNUserNotificationCenter.current().delegate = self
        UIApplication.shared.isIdleTimerDisabled = true
        
        return true
    }
}
