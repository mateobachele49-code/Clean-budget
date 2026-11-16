import UIKit
import Capacitor

/// Écran principal : on y enregistre le pont propre à Clean Budget.
class MainViewController: CAPBridgeViewController {
    override open func capacitorDidLoad() {
        bridge?.registerPluginInstance(CBBridgePlugin())
    }
}
