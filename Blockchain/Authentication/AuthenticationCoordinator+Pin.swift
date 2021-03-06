//
//  AuthenticationCoordinator+Pin.swift
//  Blockchain
//
//  Created by Chris Arriola on 4/30/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation

extension AuthenticationCoordinator: PEPinEntryControllerDelegate {

    /// Coordinates the change pin flow.
    @objc func changePin() {
        present(pinController: PEPinEntryController.pinChange()!)
    }

    /// Coordinates the pin validation flow. Primarily used to validate the user's PIN code
    /// when enabling touch ID.
    @objc func validatePin() {
        present(pinController: PEPinEntryController.pinVerifyControllerClosable()!)
    }

    // MARK: - PEPinEntryControllerDelegate

    func pinEntryControllerDidCancel(_ pinEntryController: PEPinEntryController) {
        Logger.shared.info("Pin change cancelled!")
        closePinEntryView(animated: true)
    }

    func pinEntryControllerDidObtainPasswordDecryptionKey(_ decryptionKey: String) {
        // verifyOptional indicates that the user is enabling touch ID (from settings)
        if let config = AppFeatureConfigurator.shared.configuration(for: .biometry), config.isEnabled,
            self.pinEntryViewController?.verifyOptional ?? false {
            LoadingViewPresenter.shared.hideBusyView()
            BlockchainSettings.App.shared.biometryEnabled = true
            closePinEntryView(animated: true)
            return
        }

        // Otherwise, use the decryption key to authenticate the user and download their wallet
        let encryptedPinPassword = BlockchainSettings.App.shared.encryptedPinPassword!
        guard let decryptedPassword = walletManager.wallet.decrypt(
            encryptedPinPassword,
            password: decryptionKey,
            pbkdf2_iterations: Int32(Constants.Security.pinPBKDF2Iterations)
        ), decryptedPassword.count > 0 else {
                showPinError(withMessage: LocalizationConstants.Pin.decryptedPasswordLengthZero)
                askIfUserWantsToResetPIN()
                return
        }

        let appSettings = BlockchainSettings.App.shared
        guard let guid = appSettings.guid, let sharedKey = appSettings.sharedKey else {
            AlertViewPresenter.shared.showKeychainReadError()
            return
        }

        closePinEntryView(animated: true)

        let passcodePayload = PasscodePayload(guid: guid, password: decryptedPassword, sharedKey: sharedKey)
        AuthenticationManager.shared.authenticate(using: passcodePayload, andReply: authHandler)
    }

    func pinEntryControllerDidChangePin(_ controller: PEPinEntryController) {
        // Set the last entered PIN so that during pin setting, if the user enabled biometric auth
        // we can persist the pin to the keychain
        self.lastEnteredPIN = controller.lastEnteredPin

        closePinEntryView(animated: true)

        let inSettings = pinEntryViewController?.inSettings ?? false
        if walletManager.wallet.isInitialized() && !inSettings {
            AlertViewPresenter.shared.showMobileNoticeIfNeeded()
        }
    }

    // MARK: - Private

    private func present(pinController: PEPinEntryController) {
        pinController.pinDelegate = self
        pinController.isNavigationBarHidden = true

        let peViewController = pinController.viewControllers[0] as! PEViewController
        peViewController.cancelButton.isHidden = false
        peViewController.modalTransitionStyle = .coverVertical

        self.pinEntryViewController = pinController

        if WalletManager.shared.wallet.isSyncing {
            LoadingViewPresenter.shared.showBusyView(withLoadingText: LocalizationConstants.syncingWallet)
        }

        let rootViewController = UIApplication.shared.keyWindow?.rootViewController
        rootViewController?.topMostViewController?.present(pinController, animated: true)
    }

    private func reopenChangePin() {
        closePinEntryView(animated: false)

        guard let pinViewController = PEPinEntryController.pinCreate() else {
            return
        }

        pinViewController.isNavigationBarHidden = true
        pinViewController.pinDelegate = self

        if BlockchainSettings.App.shared.isPinSet {
            pinViewController.inSettings = true
        }

        pinEntryViewController = pinViewController
        UIApplication.shared.keyWindow?.rootViewController?.present(pinViewController, animated: true)
    }

    private func askIfUserWantsToResetPIN() {
        let actions = [
            UIAlertAction(title: LocalizationConstants.Authentication.enterPassword, style: .cancel) { [unowned self] _ in
                self.closePinEntryView(animated: true)
                self.showPasswordModal()
            },
            UIAlertAction(title: LocalizationConstants.Authentication.retryValidation, style: .default) { [unowned self] _ in
                self.pinEntryViewController?.reset()
            }
        ]
        AlertViewPresenter.shared.standardNotify(
            message: LocalizationConstants.Pin.validationErrorMessage,
            title: LocalizationConstants.Pin.validationError,
            actions: actions
        )
    }

    private func showPinError(withMessage message: String) {
        invalidateLoginTimeout()
        LoadingViewPresenter.shared.hideBusyView()
        AlertViewPresenter.shared.standardNotify(message: message, title: LocalizationConstants.Errors.error) { [unowned self] _ in
            self.pinEntryViewController?.reset()
        }
    }
}
