package com.vims.app.util

import java.security.SecureRandom
import java.util.Base64
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/** Salted PBKDF2 hashing for the LOCAL auth stub only. TODO(backend): Laravel handles real credentials (bcrypt/argon2 server-side). */
object PasswordHasher {
    private const val ITERATIONS = 120_000
    private const val BITS = 256

    fun newSalt(): String = ByteArray(16).also { SecureRandom().nextBytes(it) }.let { Base64.getEncoder().encodeToString(it) }

    fun hash(password: String, salt: String): String {
        val spec = PBEKeySpec(password.toCharArray(), Base64.getDecoder().decode(salt), ITERATIONS, BITS)
        val bytes = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        spec.clearPassword()
        return Base64.getEncoder().encodeToString(bytes)
    }

    fun verify(password: String, salt: String, expected: String): Boolean {
        val a = hash(password, salt).toByteArray(); val b = expected.toByteArray()
        if (a.size != b.size) return false
        var diff = 0
        for (i in a.indices) diff = diff or (a[i].toInt() xor b[i].toInt())
        return diff == 0
    }
}
