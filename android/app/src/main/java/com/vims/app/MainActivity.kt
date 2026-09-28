package com.vims.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val bytes = assets.open("data/vims-checklists.json").use { it.readBytes().size }
        setContent { Text("VIMS toolchain check — checklist data: $bytes bytes") }
    }
}
