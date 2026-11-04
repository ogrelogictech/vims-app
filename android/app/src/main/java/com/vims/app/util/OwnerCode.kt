package com.vims.app.util

import java.security.MessageDigest
import java.util.Locale
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Shared `support.ownerCode`: strip everything but letters and digits, uppercase, PBKDF2-HMAC-SHA256 over the UTF-8 result. The
 * code itself is never in the repo or the app, only its hash. Slow on purpose (200,000 rounds), so call it off the main thread.
 */
object OwnerCode {
    fun normalize(input: String): String = input.filter { it.isLetterOrDigit() }.uppercase(Locale.ROOT)

    fun hash(input: String, salt: ByteArray, iterations: Int, bytes: Int): ByteArray {
        val spec = PBEKeySpec(normalize(input).toCharArray(), salt, iterations, bytes * 8)
        return try { SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded } finally { spec.clearPassword() }
    }

    fun matches(input: String, saltHex: String, iterations: Int, hashHex: String): Boolean {
        if (normalize(input).isEmpty() || saltHex.isEmpty() || hashHex.isEmpty() || iterations <= 0) return false
        val expected = hex(hashHex)
        return MessageDigest.isEqual(hash(input, hex(saltHex), iterations, expected.size), expected)
    }

    private fun hex(s: String): ByteArray = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
}
