---
change: keep-element-bundle-verification-clean-on-failure-and-usable-from-spaced-checkout-paths
artifact: context
---

# Context

The existing bundle checker exited from inside its try block on validation failure, skipping asynchronous cleanup. It also passed URL.pathname to the compiler, so percent-encoded spaces were treated as literal path characters. Both issues were reproduced in disposable fixtures on current main. This is a maintenance fix under the requested project audit. Human definition approval and implementation acceptance have not been recorded.
