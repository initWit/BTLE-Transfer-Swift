//
//  BTLECentralViewController.swift
//  BLTETransferSwift
//
//  Created by Robert Figueras on 2/2/16.
//  Copyright © 2016 Nerdery. All rights reserved.
//

import UIKit
import CoreBluetooth

class BTLECentralViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @IBOutlet var textview: UITextView!
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral!
    var data: NSMutableData!
    
    let TRANSFER_SERVICE_UUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    let TRANSFER_CHARACTERISTIC_UUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // initialize central manager
        centralManager = CBCentralManager(delegate: self, queue: dispatch_get_main_queue())
        
        // initialize data
        data = NSMutableData()

    }
    
    override func viewWillDisappear(animated: Bool) {
        // Don't keep it going while we're not showing
        centralManager.stopScan()
        print("Scanning stopped")
        
        super.viewWillDisappear(animated)
    }
    
    func centralManagerDidUpdateState(central : CBCentralManager) {
        
        if central.state != CBCentralManagerState.PoweredOn {
            return
        }
        
        scan()
    }
    
    /** Scan for peripherals - specifically for our service's 128bit CBUUID
     */
    func scan() {
        centralManager.scanForPeripheralsWithServices([TRANSFER_SERVICE_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey : true])
        print("1. Scanning Started")
    }
    
    
    /** This callback comes whenever a peripheral that is advertising the TRANSFER_SERVICE_UUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(central: CBCentralManager, didDiscoverPeripheral peripheral: CBPeripheral, advertisementData: [String : AnyObject], RSSI: NSNumber) {
        // Reject any where the value is above reasonable range
        if (RSSI.integerValue > -15) {
            return
        }
        
        // Reject if the signal strength is too low to be close enough (Close is around -22dB)
        if (RSSI.integerValue < -35) {
            return
        }
        
        print("2. Discovered \(peripheral.name) at \(RSSI)");
        
        // Ok, it's in range - have we already seen it?
        if (self.discoveredPeripheral != peripheral) {
            
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it
            self.discoveredPeripheral = peripheral
            
            // And connect
            print("3. Connecting to peripheral \(peripheral)")
            centralManager.connectPeripheral(peripheral, options: nil)
        }

    }
    
    
    /** If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(central: CBCentralManager, didFailToConnectPeripheral peripheral: CBPeripheral, error: NSError?) {
        
        print("Failed to connect to \(peripheral). \(error?.localizedDescription)")
        cleanup()
    }
    
    
    /** We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        print("4. Peripheral Connected")
        
        //Stop scanning
        centralManager.stopScan()
        print("5. Scanning Stopped")
        
        // Clear the data that we may already have
        data.length = 0
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self;
        
        // Search only for services that match our UUID
        peripheral.discoverServices([TRANSFER_SERVICE_UUID])
        
    }
    
    
    /** The Transfer Service was discovered
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverServices error: NSError?) {
        if ((error) != nil) {
            print("Error discovering services \(error?.localizedDescription)")
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        for service in peripheral.services! {
            peripheral.discoverCharacteristics([TRANSFER_CHARACTERISTIC_UUID], forService: service)
        }
        
    }
    
    
    /** The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(peripheral: CBPeripheral, didDiscoverCharacteristicsForService service: CBService, error: NSError?) {
        // Deal with errors (if any)
        if ((error) != nil) {
            print("Error discovering characteristics \(error?.localizedDescription)")
            cleanup()
            return;
        }
        
        // Again, we loop through the array, just in case.
        for characteristic in service.characteristics! {
            
            // And check if it's the right one
            if (characteristic.UUID == TRANSFER_CHARACTERISTIC_UUID) {
                
                // If it is, subscribe to it
                peripheral.setNotifyValue(true, forCharacteristic: characteristic)
            }
        }
        
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    
    /** This callback lets us know more data has arrived via notification on the characteristic
    */
     
    func peripheral(peripheral: CBPeripheral, didUpdateValueForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        
        if ((error) != nil) {
            print("Error discovering characteristics: \(error?.localizedDescription)")
            return
        }
        
        let stringFromData = NSString(data: characteristic.value!, encoding: NSUTF8StringEncoding)
        
        // Have we got everything we need?
        if (stringFromData == "EOM") {
            
            // We have, so show the data,
            textview.text = NSString(data: data!, encoding: NSUTF8StringEncoding)! as String
            
            // Cancel our subscription to the characteristic
            peripheral.setNotifyValue(false, forCharacteristic: characteristic)

            // and disconnect from the peripehral
            centralManager.cancelPeripheralConnection(peripheral)
        }
        
        // Otherwise, just add the data on to what we already have
        data.appendData(characteristic.value!)
        
        // Log it
        print("Received: \(stringFromData)");

    }

    
    
    /** The peripheral letting us know whether our subscribe/unsubscribe happened or not
    */
    func peripheral(peripheral: CBPeripheral, didUpdateNotificationStateForCharacteristic characteristic: CBCharacteristic, error: NSError?) {
        
        if ((error) != nil){
            print("Error changing notification state:  \(error?.localizedDescription)")
        }
        
        // Exit if it's not the transfer characteristic
        if (characteristic.UUID != [TRANSFER_CHARACTERISTIC_UUID]) {
            return
        }
        
        // Notification has started
        if (characteristic.isNotifying) {
            print("Notification began on \(characteristic)");
        }
        
        // Notification has stopped
        else {
            // so disconnect from the peripheral
            print("Notification stopped on \(characteristic).  Disconnecting");
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    
    /** Once the disconnection happens, we need to clean up our local copy of the peripheral
    */
    func centralManager(central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: NSError?)
    {
        print("6. Peripheral Disconnected \n\n\n")
        discoveredPeripheral = nil;
        
        // We're disconnected, so start scanning again
        scan()
    }
    
    
    /** Call this when things either go wrong, or you're done with the connection.
    *  This cancels any subscriptions if there are any, or straight disconnects if not.
    *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
    */
    func cleanup() {
        
        // Don't do anything if we're not connected
        if (discoveredPeripheral.state != CBPeripheralState.Connected){
            return
        }
        
        // See if we are subscribed to a characteristic on the peripheral
        // first check for any services
        guard let discoveredServices = self.discoveredPeripheral.services
            else { return } // just exit
        
        for eachService in discoveredServices {
            
            // check if there are characteristics on each service
            guard let characteristics = eachService.characteristics
                else { return } // should this be "continue"?
            
            for eachCharacteristic in characteristics {
                
                // if any characteristic is notifying, then unsubscribe
                if eachCharacteristic.UUID == [TRANSFER_CHARACTERISTIC_UUID] && eachCharacteristic.isNotifying {
                    discoveredPeripheral.setNotifyValue(false, forCharacteristic: eachCharacteristic)
                    return
                }
            }
        }
        
        // *** REFACTORED ABOVE
        // See if we are subscribed to a characteristic on the peripheral
//        if (self.discoveredPeripheral.services != nil) {
//            for service in discoveredPeripheral.services! {
//                if (service.characteristics != nil) {
//                    for characteristic in service.characteristics! {
//                        if (characteristic.UUID == [TRANSFER_CHARACTERISTIC_UUID]) {
//                            if (characteristic.isNotifying) {
//                                // It is notifying, so unsubscribe
//                                discoveredPeripheral.setNotifyValue(false, forCharacteristic: characteristic)
//                                
//                                // And we're done.
//                                return
//                            }
//                        }
//                    }
//                }
//            }
//        }
    
        // If we've got this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager .cancelPeripheralConnection(discoveredPeripheral)
    }
    
}
