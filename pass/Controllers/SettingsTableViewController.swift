//
//  SettingsTableViewController.swift
//  pass
//
//  Created by Mingshen Sun on 18/1/2017.
//  Copyright © 2017 Bob Sun. All rights reserved.
//

import UIKit
import SVProgressHUD
import CoreData
import SwiftyUserDefaults
import PasscodeLock
import LocalAuthentication

class SettingsTableViewController: UITableViewController {
    
    lazy var touchIDSwitch: UISwitch = {
        let uiSwitch = UISwitch(frame: CGRect.zero)
        uiSwitch.onTintColor = Globals.blue
        uiSwitch.addTarget(self, action: #selector(touchIDSwitchAction), for: UIControlEvents.valueChanged)
        return uiSwitch
    }()

    @IBOutlet weak var pgpKeyTableViewCell: UITableViewCell!
    @IBOutlet weak var touchIDTableViewCell: UITableViewCell!
    @IBOutlet weak var passcodeTableViewCell: UITableViewCell!
    @IBOutlet weak var passwordRepositoryTableViewCell: UITableViewCell!
    let passwordStore = PasswordStore.shared

    @IBAction func cancelPGPKey(segue: UIStoryboardSegue) {
    }
    
    @IBAction func savePGPKey(segue: UIStoryboardSegue) {
        if let controller = segue.source as? PGPKeySettingTableViewController {
            Defaults[.pgpPrivateKeyURL] = URL(string: controller.pgpPrivateKeyURLTextField.text!)
            Defaults[.pgpPublicKeyURL] = URL(string: controller.pgpPublicKeyURLTextField.text!)
            if Defaults[.isRememberPassphraseOn] {
                self.passwordStore.pgpKeyPassphrase = controller.pgpPassphrase
            }
            Defaults[.pgpKeySource] = "url"
            
            SVProgressHUD.setDefaultMaskType(.black)
            SVProgressHUD.setDefaultStyle(.light)
            SVProgressHUD.show(withStatus: "Fetching PGP Key")
            DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
                do {
                    try self.passwordStore.initPGPKey(from: Defaults[.pgpPublicKeyURL]!, keyType: .public)
                    try self.passwordStore.initPGPKey(from: Defaults[.pgpPrivateKeyURL]!, keyType: .secret)
                    DispatchQueue.main.async {
                        self.pgpKeyTableViewCell.detailTextLabel?.text = self.passwordStore.pgpKeyID
                        SVProgressHUD.showSuccess(withStatus: "Success")
                        SVProgressHUD.dismiss(withDelay: 1)
                        Utils.alert(title: "Remember to Remove the Key", message: "Remember to remove the key from the server.", controller: self, completion: nil)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.pgpKeyTableViewCell.detailTextLabel?.text = "Not Set"
                        Utils.alert(title: "Error", message: error.localizedDescription, controller: self, completion: nil)
                    }
                }
            }
            
        } else if let controller = segue.source as? PGPKeyArmorSettingTableViewController {
            Defaults[.pgpKeySource] = "armor"
            if Defaults[.isRememberPassphraseOn] {
                self.passwordStore.pgpKeyPassphrase = controller.pgpPassphrase
            }

            Defaults[.pgpPublicKeyArmor] = controller.armorPublicKeyTextView.text!
            Defaults[.pgpPrivateKeyArmor] = controller.armorPrivateKeyTextView.text!
            
            SVProgressHUD.setDefaultMaskType(.black)
            SVProgressHUD.setDefaultStyle(.light)
            SVProgressHUD.show(withStatus: "Fetching PGP Key")
            DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
                do {
                    try self.passwordStore.initPGPKey(with: controller.armorPublicKeyTextView.text, keyType: .public)
                    try self.passwordStore.initPGPKey(with: controller.armorPrivateKeyTextView.text, keyType: .secret)
                    DispatchQueue.main.async {
                        self.pgpKeyTableViewCell.detailTextLabel?.text = self.passwordStore.pgpKeyID
                        SVProgressHUD.showSuccess(withStatus: "Success")
                        SVProgressHUD.dismiss(withDelay: 1)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.pgpKeyTableViewCell.detailTextLabel?.text = "Not Set"
                        Utils.alert(title: "Error", message: error.localizedDescription, controller: self, completion: nil)
                    }
                }
            }
        }
    }
    
    private func saveImportedPGPKey() {
        // load keys
        Defaults[.pgpKeySource] = "file"
        
        SVProgressHUD.setDefaultMaskType(.black)
        SVProgressHUD.setDefaultStyle(.light)
        SVProgressHUD.show(withStatus: "Fetching PGP Key")
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            do {
                try self.passwordStore.initPGPKeys()
                DispatchQueue.main.async {
                    self.pgpKeyTableViewCell.detailTextLabel?.text = self.passwordStore.pgpKeyID
                    SVProgressHUD.showSuccess(withStatus: "Success")
                    SVProgressHUD.dismiss(withDelay: 1)
                }
            } catch {
                DispatchQueue.main.async {
                    self.pgpKeyTableViewCell.detailTextLabel?.text = "Not Set"
                    Utils.alert(title: "Error", message: error.localizedDescription, controller: self, completion: nil)
                }
            }
        }
    }
    
    @IBAction func cancelGitServerSetting(segue: UIStoryboardSegue) {
    }
    
    @IBAction func saveGitServerSetting(segue: UIStoryboardSegue) {
        self.passwordRepositoryTableViewCell.detailTextLabel?.text = Defaults[.gitURL]?.host
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Security section, hide TouchID if the device doesn't support
        if section == 1 {
            if hasTouchID() {
                return 2
            } else {
                return 1
            }
        }
        return super.tableView(tableView, numberOfRowsInSection: section)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsTableViewController.actOnPasswordStoreErasedNotification), name: .passwordStoreErased, object: nil)
        self.passwordRepositoryTableViewCell.detailTextLabel?.text = Defaults[.gitURL]?.host
        touchIDTableViewCell.accessoryView = touchIDSwitch
        setPGPKeyTableViewCellDetailText()
        setPasswordRepositoryTableViewCellDetailText()
        setPasscodeLockTouchIDCells()
    }
    
    private func hasTouchID() -> Bool {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(LAPolicy.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return true
        } else {
            switch error!.code {
            case LAError.Code.touchIDNotEnrolled.rawValue:
                return true
            case LAError.Code.passcodeNotSet.rawValue:
                return true
            default:
                return false
            }
        }
    }
    
    private func isTouchIDEnabled() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }
    
    private func setPasscodeLockTouchIDCells() {
        if PasscodeLockRepository().hasPasscode {
            self.passcodeTableViewCell.detailTextLabel?.text = "On"
            Globals.passcodeConfiguration.isTouchIDAllowed = true
            touchIDSwitch.isOn = Defaults[.isTouchIDOn]
        } else {
            self.passcodeTableViewCell.detailTextLabel?.text = "Off"
            Globals.passcodeConfiguration.isTouchIDAllowed = false
            Defaults[.isTouchIDOn] = false
            touchIDSwitch.isOn = Defaults[.isTouchIDOn]
        }
    }
    
    private func setPGPKeyTableViewCellDetailText() {
        if let pgpKeyID = self.passwordStore.pgpKeyID {
            pgpKeyTableViewCell.detailTextLabel?.text = pgpKeyID
        } else {
            pgpKeyTableViewCell.detailTextLabel?.text = "Not Set"
        }
    }
    
    private func setPasswordRepositoryTableViewCellDetailText() {
        if Defaults[.gitURL] == nil {
            passwordRepositoryTableViewCell.detailTextLabel?.text = "Not Set"
        } else {
            passwordRepositoryTableViewCell.detailTextLabel?.text = Defaults[.gitURL]!.host
        }
    }
    
    func actOnPasswordStoreErasedNotification() {
        setPGPKeyTableViewCellDetailText()
        setPasswordRepositoryTableViewCellDetailText()
        setPasscodeLockTouchIDCells()

        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.passcodeLockPresenter = PasscodeLockPresenter(mainWindow: appDelegate.window, configuration: Globals.passcodeConfiguration)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.cellForRow(at: indexPath) == passcodeTableViewCell {
            if Defaults[.passcodeKey] != nil{
                showPasscodeActionSheet()
            } else {
                setPasscodeLock()
            }
        } else if tableView.cellForRow(at: indexPath) == pgpKeyTableViewCell {
            showPGPKeyActionSheet()
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func touchIDSwitchAction(uiSwitch: UISwitch) {
        if !Globals.passcodeConfiguration.isTouchIDAllowed || !isTouchIDEnabled() {
            // switch off
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                uiSwitch.isOn = Defaults[.isTouchIDOn]  // false
                Utils.alert(title: "Notice", message: "Please enable Touch ID and set the passcode lock first.", controller: self, completion: nil)
            }
        } else {
            Defaults[.isTouchIDOn] = uiSwitch.isOn
        }
        let appDelegate = UIApplication.shared.delegate as! AppDelegate
        appDelegate.passcodeLockPresenter = PasscodeLockPresenter(mainWindow: appDelegate.window, configuration: Globals.passcodeConfiguration)
    }
    
    func showPGPKeyActionSheet() {
        let optionMenu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        var urlActionTitle = "Download from URL"
        var armorActionTitle = "ASCII-Armor Encrypted Key"
        var fileActionTitle = "Use Imported Keys"
        
        if Defaults[.pgpKeySource] == "url" {
           urlActionTitle = "✓ \(urlActionTitle)"
        } else if Defaults[.pgpKeySource] == "armor" {
            armorActionTitle = "✓ \(armorActionTitle)"
        } else if Defaults[.pgpKeySource] == "file" {
            fileActionTitle = "✓ \(fileActionTitle)"
        }
        let urlAction = UIAlertAction(title: urlActionTitle, style: .default) { _ in
            self.performSegue(withIdentifier: "setPGPKeyByURLSegue", sender: self)
        }
        let armorAction = UIAlertAction(title: armorActionTitle, style: .default) { _ in
            self.performSegue(withIdentifier: "setPGPKeyByASCIISegue", sender: self)
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        optionMenu.addAction(urlAction)
        optionMenu.addAction(armorAction)

        if passwordStore.pgpKeyExists() {
            let fileAction = UIAlertAction(title: fileActionTitle, style: .default) { _ in
                // passphrase related
                let savePassphraseAlert = UIAlertController(title: "Passphrase", message: "Do you want to save the passphrase for later decryption?", preferredStyle: UIAlertControllerStyle.alert)
                // no
                savePassphraseAlert.addAction(UIAlertAction(title: "No", style: UIAlertActionStyle.default) { _ in
                    self.passwordStore.pgpKeyPassphrase = nil
                    Defaults[.isRememberPassphraseOn] = false
                    self.saveImportedPGPKey()
                })
                // yes
                savePassphraseAlert.addAction(UIAlertAction(title: "Yes", style: UIAlertActionStyle.destructive) {_ in
                    // ask for the passphrase
                    let alert = UIAlertController(title: "Passphrase", message: "Please fill in the passphrase of your PGP secret key.", preferredStyle: UIAlertControllerStyle.alert)
                    alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: {_ in
                        self.passwordStore.pgpKeyPassphrase = alert.textFields?.first?.text
                        Defaults[.isRememberPassphraseOn] = true
                        self.saveImportedPGPKey()
                    }))
                    alert.addTextField(configurationHandler: {(textField: UITextField!) in
                        textField.text = ""
                        textField.isSecureTextEntry = true
                    })
                    self.present(alert, animated: true, completion: nil)
                })
                self.present(savePassphraseAlert, animated: true, completion: nil)
            }
            optionMenu.addAction(fileAction)
        } else {
            let fileAction = UIAlertAction(title: "iTunes File Sharing", style: .default) { _ in
                let title = "Import via iTunes File Sharing"
                let message = "Copy your public and private key from your computer to Pass for iOS with the name \"gpg_key.pub\" and \"gpg_key\" (without quotes)."
                Utils.alert(title: title, message: message, controller: self)
            }
            optionMenu.addAction(fileAction)
        }
        
        
        if Defaults[.pgpKeySource] != nil {
            let deleteAction = UIAlertAction(title: "Remove PGP Keys", style: .destructive) { _ in
                self.passwordStore.removePGPKeys()
                self.pgpKeyTableViewCell.detailTextLabel?.text = "Not Set"
            }
            optionMenu.addAction(deleteAction)
        }
        optionMenu.addAction(cancelAction)
        optionMenu.popoverPresentationController?.sourceView = pgpKeyTableViewCell
        optionMenu.popoverPresentationController?.sourceRect = pgpKeyTableViewCell.bounds
        self.present(optionMenu, animated: true, completion: nil)
    }
    
    func showPasscodeActionSheet() {
        let passcodeChangeViewController = PasscodeLockViewController(state: .change, configuration: Globals.passcodeConfiguration)
        let passcodeRemoveViewController = PasscodeLockViewController(state: .remove, configuration: Globals.passcodeConfiguration)

        let optionMenu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let removePasscodeAction = UIAlertAction(title: "Remove Passcode", style: .destructive) { [weak self] _ in
            passcodeRemoveViewController.successCallback  = { _ in
                self?.setPasscodeLockTouchIDCells()
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                appDelegate.passcodeLockPresenter = PasscodeLockPresenter(mainWindow: appDelegate.window, configuration: Globals.passcodeConfiguration)
            }
            self?.present(passcodeRemoveViewController, animated: true, completion: nil)
        }
        
        let changePasscodeAction = UIAlertAction(title: "Change Passcode", style: .default) { [weak self] _ in
            self?.present(passcodeChangeViewController, animated: true, completion: nil)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        optionMenu.addAction(removePasscodeAction)
        optionMenu.addAction(changePasscodeAction)
        optionMenu.addAction(cancelAction)
        optionMenu.popoverPresentationController?.sourceView = passcodeTableViewCell
        optionMenu.popoverPresentationController?.sourceRect = passcodeTableViewCell.bounds
        self.present(optionMenu, animated: true, completion: nil)
    }
    
    func setPasscodeLock() {
        let passcodeSetViewController = PasscodeLockViewController(state: .set, configuration: Globals.passcodeConfiguration)
        passcodeSetViewController.successCallback = { _ in
            self.setPasscodeLockTouchIDCells()
        }
        present(passcodeSetViewController, animated: true, completion: nil)
    }
}
