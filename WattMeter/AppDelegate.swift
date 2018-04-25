//
//  AppDelegate.swift
//  WattMeter
//
//  Created by Lander Noterman on 24/04/2018.
//  Copyright © 2018 Lander Noterman. All rights reserved.
//

import Cocoa
import Foundation
import IOKit.ps
import IOKit.pwr_mgt


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
        
        var watts = 0
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSource = IOPSGetProvidingPowerSourceType(psInfo).takeRetainedValue() as String
        if powerSource == kIOPMACPowerKey {
            let acInfo = IOPSCopyExternalPowerAdapterDetails().takeRetainedValue() as CFTypeRef
            if let acWatts = (acInfo[kIOPSPowerAdapterWattsKey] as? Int) {
                watts = acWatts
                iconText += "⚡️"
            }
        } else if powerSource == kIOPMBatteryPowerKey {
            var voltage = 0
            var current = 0
            
            // OMG, kill me now
            var kernResult: kern_return_t?
            let tmp: UnsafeMutablePointer<Unmanaged<CFArray>?> = UnsafeMutablePointer.allocate(capacity: MemoryLayout<Unmanaged<CFArray>?>.size)
            let masterPort: UnsafeMutablePointer<mach_port_t> = UnsafeMutablePointer.allocate(capacity: MemoryLayout<mach_port_t>.size)
            kernResult = IOMasterPort(mach_port_t(MACH_PORT_NULL), masterPort)
            if KERN_SUCCESS != kernResult {
                print("Something went wrong.")
            } else {
                IOPMCopyBatteryInfo(mach_port_t(MACH_PORT_NULL), tmp)
                let array:CFArray = (tmp.pointee?.takeRetainedValue())!
                let count = CFArrayGetCount(array)
                if count > 0 {
                    let pointer = CFArrayGetValueAtIndex(array, 0)
                    let pmBattery:Dictionary<String, Any> = unsafeBitCast(pointer, to: CFDictionary.self) as! Dictionary
                    voltage = pmBattery[kIOBatteryVoltageKey] as! Int
                    current = pmBattery[kIOBatteryAmperageKey] as! Int
                }
            }
            
            /*
            // This is a better way to get above info, but unfortunately doesn't work for voltage for some reason
            let psList = IOPSCopyPowerSourcesList(psInfo).takeRetainedValue() as [CFTypeRef]
            for ps in psList {
                let psDesc2 = IOPSGetPowerSourceDescription(psInfo, ps)
                if let psDesc = IOPSGetPowerSourceDescription(psInfo, ps).takeUnretainedValue() as? [String: Any] {
                    if let battVoltage = (psDesc[kIOPSVoltageKey] as? Int) {
                        print("Voltage:", battVoltage)
                        voltage = battVoltage
                    }
                    if let battCurrent = (psDesc[kIOPSCurrentKey] as? Int) {
                        print("Current:", battCurrent)
                        current = battCurrent
                    }
                    
                }
            }
            */
            
            watts = abs(voltage / 1000 * current / 1000)
            
            // TODO: Get more reliable way of selecting model?
            let model = "MacBook Pro"
            let cores = 4
            
            
            let impact = get_impact(model: model, cores: cores, watt: watts)
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
        
        attribute[NSAttributedStringKey.font] = NSFont(name: "Helvetica", size: 10)
        
        if let button = statusItem.button {
            iconText += String(watts) + "W"
            button.attributedTitle = NSAttributedString(string: iconText, attributes: attribute)
        }
    }
    
    func get_impact(model: String, cores: Int, watt: Int) -> String{
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
        if let low = IMPACT[cores]?[model]?["low"],
        let medium = IMPACT[cores]?[model]?["medium"],
        let high = IMPACT[cores]?[model]?["high"] {
            if watt <= low{
                return "low"
            }
            if watt <= medium{
                return "medium"
            }
            if watt >= high{
                return "high"
            }
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

