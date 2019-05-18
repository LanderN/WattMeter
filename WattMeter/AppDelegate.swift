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
import LaunchAtLogin

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

struct Statistics {
    var voltage: Double
    var current: Double
    var watts: Int
}

struct ImpactDefinition {
    var high = 40
    var normal = 20
    var low = 15
}

enum Impact {
    case LOW
    case NORMAL
    case HIGH
    case VERY_HIGH
}

enum PowerSource {
    case AC
    case BATTERY
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var updateTimer:Timer!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var launchAtLoginItem:NSMenuItem!

    func getBatteryStatistics() -> Statistics {
        var voltage = 0.0
        var current = 0.0
        
        // Get current and voltage from battery
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
                voltage = (pmBattery[kIOBatteryVoltageKey] as! Double) / 1000.0
                current = (pmBattery[kIOBatteryAmperageKey] as! Double) / 1000.0
            }
        }
        
        let watts = Int(floor(abs(voltage * current)))
        return Statistics(voltage: voltage, current: current, watts: watts)
    }
    
    func getColor(impact: Impact) -> NSColor {
        // TODO: Replace by user preference
        switch impact {
        case Impact.LOW:
            return NSColor(rgb:0x3D9140)
        case Impact.NORMAL:
            return NSColor(rgb:0x7b917b)
        case Impact.HIGH:
            return NSColor(rgb:0xDD8000)
        case Impact.VERY_HIGH:
            return NSColor(rgb:0xff0000)
        }
    }
    
    func getModel() -> String {
        let service: io_service_t = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        let cfstr = "model" as CFString
        if let model = IORegistryEntryCreateCFProperty(service, cfstr, kCFAllocatorDefault, 0).takeUnretainedValue() as? NSData {
            if let nsstr =  NSString(data: model as Data, encoding: String.Encoding.utf8.rawValue) {
                return nsstr as String
            }
        }
        return ""
    }
    
    func getPowerSource() -> PowerSource {
        let psInfo = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let powerSource = IOPSGetProvidingPowerSourceType(psInfo).takeRetainedValue() as String
        if powerSource == kIOPMACPowerKey {
            return PowerSource.AC
        } else {
            return PowerSource.BATTERY
        }
    }
    
    @objc func updateIcon() {
        var iconAttributes = [:] as [NSAttributedStringKey: Any]
        var iconText = ""
        var watts = 0
        
        if getPowerSource() == PowerSource.AC {
            let acInfo = IOPSCopyExternalPowerAdapterDetails().takeRetainedValue() as CFTypeRef
            if let acWatts = (acInfo[kIOPSPowerAdapterWattsKey] as? Int) {
                watts = acWatts
                iconText += "⚡️"
            }
            
        } else if getPowerSource() == PowerSource.BATTERY {
            watts = getBatteryStatistics().watts
            let impact = getImpact(model: getModel(), watt: watts)
            
            if impact == Impact.VERY_HIGH {
                iconText += "⚠ "
            }
            
            iconAttributes[NSAttributedStringKey.foregroundColor] = getColor(impact: impact)
        }
        
        iconAttributes[NSAttributedStringKey.font] = NSFont(name: "Helvetica", size: 10)
        
        if let button = statusItem.button {
            iconText += String(watts) + "W"
            button.attributedTitle = NSAttributedString(string: iconText, attributes: iconAttributes)
            button.action = #selector(self.constructMenu)
        }
        redrawMenu(menu: statusItem.menu!)
    }
    
    func getImpact(model: String, watt: Int) -> Impact{
        // TODO: Replace by user preference if desired
        var impact: ImpactDefinition
        if model.contains("MacBookPro13,3") {
            impact = ImpactDefinition(high:40, normal: 20, low: 15)
            // TODO: Add more model definitions
        } else {
            impact = ImpactDefinition()
        }
        
        if watt <= impact.low{
            return Impact.LOW
        }
        if watt <= impact.normal{
            return Impact.NORMAL
        }
        if watt <= impact.high{
            return Impact.HIGH
        }
        return Impact.VERY_HIGH
        
        
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        updateTimer = Timer.scheduledTimer(timeInterval: 40.0, target: self, selector: #selector(AppDelegate.updateIcon), userInfo: nil, repeats: true)
        constructMenu()
        updateIcon()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    @objc func toggleLaunchAtLogin() {
        LaunchAtLogin.isEnabled = !LaunchAtLogin.isEnabled
        if(LaunchAtLogin.isEnabled) {
            launchAtLoginItem.state = NSControl.StateValue.on
        } else {
            launchAtLoginItem.state = NSControl.StateValue.off
        }
    }
    
    @objc func redrawMenu(menu: NSMenu) {
        menu.removeAllItems()
        if (getPowerSource() == PowerSource.BATTERY) {
            menu.addItem(NSMenuItem(title: "Using Battery Power", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Voltage: " + String(getBatteryStatistics().voltage) + "V", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Current: " + String(abs(getBatteryStatistics().current)) + "A", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Using AC Power", action: nil, keyEquivalent: ""))
        }
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(AppDelegate.toggleLaunchAtLogin), keyEquivalent: "")
        if(LaunchAtLogin.isEnabled) {
            launchAtLoginItem.state = NSControl.StateValue.on
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(NSMenuItem(title: "Quit Wattmeter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func constructMenu() {
        statusItem.menu = NSMenu()
        redrawMenu(menu: statusItem.menu!)
    }
}

