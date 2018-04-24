//
//  AppDelegate.swift
//  WattMeter
//
//  Created by Lander Noterman on 24/04/2018.
//  Copyright © 2018 Lander Noterman. All rights reserved.
//

import Cocoa
import Foundation


// Copied from StackOverflow
// https://stackoverflow.com/a/24263296
extension NSColor {
    convenience init(red: Int, green: Int, blue: Int) {
        assert(red >= 0 && red <= 255, "Invalid red component")
        assert(green >= 0 && green <= 255, "Invalid green component")
        assert(blue >= 0 && blue <= 255, "Invalid blue component")
        
        self.init(red: CGFloat(red) / 255.0, green: CGFloat(green) / 255.0, blue: CGFloat(blue) / 255.0, alpha: 1.0)
    }
    
    convenience init(rgb: Int) {
        self.init(
            red: (rgb >> 16) & 0xFF,
            green: (rgb >> 8) & 0xFF,
            blue: rgb & 0xFF
        )
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var updateTimer:Timer!
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    @objc func updateIcon() {
        var attribute = [:] as [NSAttributedStringKey: Any]
        var iconText = ""
        
        // TODO: Split this off into other method
        // Create a Task instance
        let task = Process()
        
        // Set the task parameters
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["-xml", "SPPowerDataType", "SPHardwareDataType"]
        
        // Create a Pipe and make the task
        // put all the output there
        let pipe = Pipe()
        task.standardOutput = pipe
        
        // Launch the task
        task.launch()
        
        
        // Get the data
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WattInfo")
        do {
            try data.write(to: path, options: .atomic)
        } catch {
            // TODO: error handling
            print(error)
        }
        
        // TODO: Write a better way of retrieving values
        let resultArray = NSArray(contentsOf: path)
        
        let result = resultArray![0] as! NSDictionary
        let items = result.value(forKey: "_items") as! NSArray
        let spbattery_info = items[0] as! NSDictionary
        let spac_info = items[1] as! NSDictionary
        let spac_info2 = items[3] as! NSDictionary
        
        let current_amperage = spbattery_info.value(forKey: "sppower_current_amperage") as! Int
        let current_voltage = spbattery_info.value(forKey: "sppower_current_voltage") as! Int
        var current_watt = String(abs(current_voltage / 1000 * current_amperage / 1000))
        
        let result1 = resultArray![1] as! NSDictionary
        let items1 = result1.value(forKey: "_items") as! NSArray
        let machine_info = items1[0] as! NSDictionary
        // TODO: Get more reliable way of selecting model?
        let model = machine_info.value(forKey: "machine_name") as! String
        let cores = Int(machine_info.value(forKey: "number_processors") as! Int)
        

        if let ac = spac_info.value(forKey: "AC Power") as! NSDictionary? {
            if ac.value(forKey: "Current Power Source") != nil {
                current_watt = spac_info2.value(forKey: "sppower_ac_charger_watts") as! String
                iconText += "⚡️"
            }
        else {
            let machine = [
                "model": model,
                "cores": cores,
                "current_watt": current_watt
                ] as [String : Any]
            let impact = get_impact(machine: machine)
            var color = NSColor(rgb:0xDD8000)
            if impact == "low"{
            color = NSColor(rgb:0x3D9140)
            }
            if impact == "medium"{
            color = NSColor(rgb:0x7b917b)
            }
            if impact == "high"{
            color = NSColor(rgb:0xff0000)
            }
            if impact == "high"{
            iconText += "⚠ "
            }
            
            attribute[NSAttributedStringKey.foregroundColor] = color
        }
        }
        
        attribute[NSAttributedStringKey.font] = NSFont(name: "Helvetica", size: 10)
        
        if let button = statusItem.button {
            iconText += current_watt + "W"
            button.attributedTitle = NSAttributedString(string: iconText, attributes: attribute)
        }
    }
    
    func get_impact(machine: Dictionary<String, Any>) -> String{
        // TODO: Update this to reflect all available models
        // TODO: Add fallback for unrecognized Macs
        // TODO: Make configurable in settings, with reasonable defaults for detected model
        let IMPACT = [
            2: [
                "MacBook Air": [
                    "high": 20,
                    "low": 10
                ],
                "MacBook Pro": [
                    "high": 50,
                    "low": 20
                ]
            ],
            4: [
                "MacBook Pro": [
                    "high": 40,
                    "medium": 20,
                    "low": 15
                ]
            ]
        ]
        
        // TODO: Clean up this mess
        let model = machine["model"] as! String
        let cores = machine["cores"] as! Int
        let watt = Int(machine["current_watt"] as! String)
        let low = IMPACT[cores]![model]!["low"]
        let medium = IMPACT[cores]![model]!["medium"]
        let high = IMPACT[cores]![model]!["high"]
        if watt! <= low!{
            return "low"
        }
        if watt! <= medium!{
            return "medium"
        }
        if watt! >= high!{
            return "high"
        }
        return "mid"
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        updateTimer = Timer.scheduledTimer(timeInterval: 40.0, target: self, selector: #selector(AppDelegate.updateIcon), userInfo: nil, repeats: true)
        updateIcon()
        constructMenu()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    func constructMenu() {
        let menu = NSMenu()
        // TODO: add extra info here (Voltage, Amperage)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Wattmeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
}

