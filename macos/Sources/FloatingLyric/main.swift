import FloatingLyricCore

// Top-level code runs on the main thread, but is not statically main-actor
// isolated, so state the guarantee explicitly.
MainActor.assumeIsolated {
    FloatingLyricApp.run()
}
