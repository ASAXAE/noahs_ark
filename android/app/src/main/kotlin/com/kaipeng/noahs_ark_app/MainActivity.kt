package com.kaipeng.noahs_ark_app

import io.flutter.embedding.android.FlutterActivity
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        // 允许所有键盘事件通过，包括数字键用于选择候选词
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        return super.onKeyUp(keyCode, event)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        // 确保所有键盘事件都能正确分发
        return super.dispatchKeyEvent(event)
    }
}
