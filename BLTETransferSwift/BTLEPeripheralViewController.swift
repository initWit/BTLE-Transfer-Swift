//
//  BTLEPeripheralViewController.swift
//  BLTETransferSwift
//
//  Created by Robert Figueras on 2/3/16.
//  Copyright © 2016 Nerdery. All rights reserved.
//

import UIKit
import CoreBluetooth

class BTLEPeripheralViewController: UIViewController, CBPeripheralManagerDelegate, UITextViewDelegate {

    @IBOutlet var textview: UITextView!
    @IBOutlet var advertisingSwitch : UISwitch!
    
    var peripheralManager: CBPeripheralManager!
    var transferCharacteristic: CBMutableCharacteristic!
    var dataToSend: NSData!
    var sendDataIndex: NSInteger!
    
    let TRANSFER_SERVICE_UUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    let TRANSFER_CHARACTERISTIC_UUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
    let NOTIFY_MTU = 20

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Start up the CBPeripheralManager
        peripheralManager = CBPeripheralManager(delegate: self, queue: dispatch_get_main_queue())
        
    }
    
    
    override func viewWillAppear(animated: Bool) {
        
        // Don't keep it going while we're not showing.
        peripheralManager.stopAdvertising()
        super.viewWillAppear(animated)
    }
    
    
    /** Required protocol method.  A full app should take care of all the possible states,
    *  but we're just waiting for  to know when the CBPeripheralManager is ready
    */
    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        
        // Opt out from any other state
        if (peripheral.state != CBPeripheralManagerState.PoweredOn) {
            return
        }
        
        // We're in CBPeripheralManagerStatePoweredOn state...
        print("peripheralManager powered on.")
        
        // Start with the CBMutableCharacteristic
        transferCharacteristic = CBMutableCharacteristic(type: TRANSFER_CHARACTERISTIC_UUID,
            properties: CBCharacteristicProperties.Notify,
            value: nil ,
            permissions: CBAttributePermissions.Readable)
        
        // Then the service
        let transferService = CBMutableService(type: TRANSFER_SERVICE_UUID, primary: true)
        
        // Add the characteristic to the service
        transferService.characteristics = [transferCharacteristic]
        
        // And add it to the peripheral manager
        peripheralManager.addService(transferService)
    
    }


    /** Catch when someone subscribes to our characteristic, then start sending them data
    */
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didSubscribeToCharacteristic characteristic: CBCharacteristic) {
        print("Central subscribed to characteristic")
        
        // Get the data
        dataToSend = self.textview.text.dataUsingEncoding(NSUTF8StringEncoding)
        
        // Reset the index
        sendDataIndex = 0
        
        // Start sending
        sendData()
        
    }
    
    
    
    /** Recognise when the central unsubscribes
     */
    func peripheralManager(peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFromCharacteristic characteristic: CBCharacteristic) {
        print("Central unsubscribed from characteristic")
    }
    
    
    /** Sends the next amount of data to the connected central
     */
    func sendData(){
        // First up, check if we're meant to be sending an EOM
        var sendingEOM = false
        
        if (sendingEOM ) {
            
            let updateDataString = "EOM"
            
            // send it
            var didSend = peripheralManager.updateValue(updateDataString.dataUsingEncoding(NSUTF8StringEncoding)!, forCharacteristic: transferCharacteristic, onSubscribedCentrals: nil)
            
            // Did it send?
            if (didSend) {
                
                // It did, so mark it as sent
                sendingEOM = false
                print("Sent: EOM")
            }
            
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        
        // Is there any left to send?
        
        if (sendDataIndex >= dataToSend.length){
            // No data left. Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true
        
        while (didSend){
            // Make the next chunk
            
            // Work out how big it should be
            var amountToSend = dataToSend.length - sendDataIndex
            
            // Can't be longer than 20 bytes
            if (amountToSend > NOTIFY_MTU){
                amountToSend = NOTIFY_MTU
            }
            
            // Copy out the data we want
            let chunk = NSData(bytes: dataToSend.bytes + sendDataIndex, length: amountToSend)
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, forCharacteristic: transferCharacteristic, onSubscribedCentrals: nil)
            
            // If it didn't work, drop out and wait for the callback
            if(!didSend){
                return
            }
            
            let stringFromData = NSString(data: chunk, encoding: NSUTF8StringEncoding)
            print("Sent: \(stringFromData)")
            
            // It did send, so update our index
            sendDataIndex = sendDataIndex + amountToSend
            
            // Was it the last one?
            if(sendDataIndex >= dataToSend.length){
                
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it the next time
                sendingEOM = true
                
                // Send it
                let updateDataString = "EOM"
                let eomSent = peripheralManager.updateValue(updateDataString.dataUsingEncoding(NSUTF8StringEncoding)!, forCharacteristic: transferCharacteristic, onSubscribedCentrals: nil)
                
                if (eomSent) {
                    sendingEOM = false
                    print("Sent: EOM")
                }
                
                return
                
            }
            
        }
        
    }
    
    
    /** This callback comes in when the PeripheralManager is ready to send the next chunk of data.
    *  This is to ensure that packets will arrive in the order they are sent
    */
    func peripheralManagerIsReadyToUpdateSubscribers(peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }
    
    
    /** This is called when a change happens, so we know to stop advertising
    */
    func textViewDidChange(textView: UITextView) {
        // If we're already advertising, stop
        if (advertisingSwitch.on) {
            advertisingSwitch.setOn(false, animated: false)
            peripheralManager .stopAdvertising()
        }
    }
    
    
    /** Adds the 'Done' button to the title bar
    */
    func textViewDidBeginEditing(textView: UITextView) {
        // We need to add this manually so we have a way to dismiss the keyboard
        let rightButton = UIBarButtonItem(barButtonSystemItem: .Done, target: self, action: "dismissKeyboard")
        self.navigationItem.rightBarButtonItem = rightButton
    }
    
    
    /** Finishes the editing */
    func dismissKeyboard() {
        self.textview.resignFirstResponder()
        self.navigationItem.rightBarButtonItem = nil;
    }
    
    
    /** Start advertising
    */
    @IBAction func switchChanged(sender: UIButton) {
        
        if (advertisingSwitch.on) {
            // All we advertise is our service's UUID
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey : TRANSFER_SERVICE_UUID])
        } else {
            peripheralManager.stopAdvertising()
        }
    }
    
} // end class