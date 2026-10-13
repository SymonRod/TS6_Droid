package com.flammedemon.ts6_flutter

import android.content.Context

/** Loads the Rust bridge and hands it the app Context (needed before connecting). */
object NativeInit {
    private var done = false

    external fun initContext(context: Context)

    fun init(context: Context) {
        if (done) return
        System.loadLibrary("tslib_frb")
        initContext(context.applicationContext)
        done = true
    }
}
