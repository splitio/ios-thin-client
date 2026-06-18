# Harness FME Thin Client SDK for iOS

## Overview
This SDK is designed to work with Harness FME, the platform for controlled rollouts, which serves features to your users via feature flags to manage your complete customer experience.

The thin client delegates flag evaluation to the Remote Evaluator service.

## Compatibility
This SDK is compatible with iOS 13 and later, and macOS 10.15 and later. It requires Swift 5.5 or later.

## Installation

Add the SDK as a Swift Package Manager dependency.

In Xcode: **File → Add Package Dependencies…** and enter the repository URL, or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/splitio/ios-thin-client.git", from: "1.0.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SplitThin", package: "ios-thin-client"),
        ]
    ),
]
```

## Getting started

Below is a simple example that describes the instantiation and most basic usage of the SDK.

```swift
import SplitThin

final class ViewController: UIViewController {

    private var client: SplitClient?

    func setupSplit() {
        let config = SplitClientConfig.builder()
                                      .set(logLevel: .verbose)
                                      .set(syncMode: .streaming)
                                      .set(evaluationRefreshRate: 60)
                                      .build()

        let target = Target(key: Key(matchingKey: "CUSTOMER_ID"), trafficType: "user")

        let factory = DefaultSplitFactoryBuilder().setSdkKey(SdkKey("YOUR_SDK_KEY"))
                                                  .setTarget(target)
                                                  .setConfig(config)
                                                  .build()

        guard let client = factory?.client else { return }
        self.client = client

        // Receive events from the SDK (ready, update, etc)
        let listener = SplitListener(client: client, viewController: self)
        client.addEventListener(listener)
    }

    func updateUI(treatment: String) {
        // someButton.setTitle(treatment, for: .normal)
    }
}

final class SplitListener: SplitEventListener {
    weak var client: SplitClient?
    weak var viewController: ViewController?

    init(client: SplitClient, viewController: ViewController) {
        self.client = client
        self.viewController = viewController
    }

    func onReady(_ metadata: SdkReadyMetadata) {
        print("Split SDK Ready")
        let result = client?.getTreatment(flag: "FEATURE_FLAG_NAME")
        viewController?.updateUI(treatment: result?.treatment ?? "control")
    }

    func onUpdate(_ metadata: SdkUpdateMetadata) {
        guard let client = client, let updatedFlag = metadata.names.first else {
            return
        }
        
        let result = client.getTreatment(flag: updatedFlag)
        print("Flag \(updatedFlag) updated, new treatment: \(result.treatment)")
    }
}
```

## Submitting issues

The team monitors all issues submitted to this [issue tracker](https://github.com/splitio/ios-thin-client/issues). We encourage you to use this issue tracker to submit any bug reports, feedback, and feature enhancements. We'll do our best to respond in a timely manner.

## License
Licensed under the Apache License, Version 2.0. See: [Apache License](http://www.apache.org/licenses/).
