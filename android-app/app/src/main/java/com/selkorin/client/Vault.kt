package com.selkorin.client

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

/**
 * Зашифрованное хранилище ключей пользователя.
 * Пароль пользователя (через PBKDF2, 210 000 итераций) выводит AES-256 ключ,
 * которым шифруется каждый секрет (AES/GCM). Ничего не читается без
 * разблокировки паролем или биометрией (см. BiometricHelper).
 */
class Vault(context: Context) {

    data class KeyMeta(val id: String, val name: String, val type: String, val addedAt: Long)

    private val prefs = context.applicationContext
        .getSharedPreferences("selkorin_vault", Context.MODE_PRIVATE)

    private var sessionKey: SecretKey? = null

    fun isConfigured(): Boolean = prefs.contains("salt")
    fun isUnlocked(): Boolean = sessionKey != null

    private fun deriveKey(password: String, salt: ByteArray): SecretKey {
        val spec = PBEKeySpec(password.toCharArray(), salt, 210_000, 256)
        val raw = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
        return SecretKeySpec(raw, "AES")
    }

    private fun encrypt(key: SecretKey, plaintext: String): Pair<String, String> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        val ct = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(iv, Base64.NO_WRAP) to Base64.encodeToString(ct, Base64.NO_WRAP)
    }

    private fun decrypt(key: SecretKey, ivB64: String, ctB64: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
        val pt = cipher.doFinal(Base64.decode(ctB64, Base64.NO_WRAP))
        return String(pt, Charsets.UTF_8)
    }

    fun setupPassword(password: String) {
        require(password.length >= 4) { "Пароль минимум 4 символа" }
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(password, salt)
        val (iv, ct) = encrypt(key, VERIFIER)
        prefs.edit()
            .putString("salt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString("verifier_iv", iv)
            .putString("verifier_ct", ct)
            .apply()
        sessionKey = key
    }

    fun unlock(password: String): Boolean {
        val saltB64 = prefs.getString("salt", null) ?: return false
        val iv = prefs.getString("verifier_iv", null) ?: return false
        val ct = prefs.getString("verifier_ct", null) ?: return false
        val salt = Base64.decode(saltB64, Base64.NO_WRAP)
        val key = deriveKey(password, salt)
        return try {
            if (decrypt(key, iv, ct) == VERIFIER) { sessionKey = key; true } else false
        } catch (e: Exception) { false }
    }

    fun lock() { sessionKey = null }

    fun changePassword(oldPass: String, newPass: String) {
        require(unlock(oldPass)) { "Старый пароль неверен" }
        val oldKey = sessionKey!!
        val keys = readKeys()
        val secrets = keys.map { decrypt(oldKey, it.getString("iv"), it.getString("ct")) }
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val newKey = deriveKey(newPass, salt)
        val (vIv, vCt) = encrypt(newKey, VERIFIER)
        val reEncrypted = JSONArray()
        for (i in 0 until keys.length()) {
            val k = keys.getJSONObject(i)
            val (iv, ct) = encrypt(newKey, secrets[i])
            reEncrypted.put(JSONObject().apply {
                put("id", k.getString("id")); put("name", k.getString("name"))
                put("type", k.getString("type")); put("addedAt", k.getLong("addedAt"))
                put("iv", iv); put("ct", ct)
            })
        }
        prefs.edit()
            .putString("salt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString("verifier_iv", vIv).putString("verifier_ct", vCt)
            .putString("keys", reEncrypted.toString())
            .apply()
        sessionKey = newKey
    }

    private fun readKeys(): JSONArray = JSONArray(prefs.getString("keys", "[]"))

    private fun requireUnlocked(): SecretKey = sessionKey ?: throw IllegalStateException("Приложение заблокировано")

    fun listKeys(): List<KeyMeta> {
        requireUnlocked()
        val arr = readKeys()
        return (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            KeyMeta(o.getString("id"), o.getString("name"), o.getString("type"), o.getLong("addedAt"))
        }
    }

    fun getSecret(id: String): String {
        val key = requireUnlocked()
        val arr = readKeys()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getString("id") == id) return decrypt(key, o.getString("iv"), o.getString("ct"))
        }
        throw IllegalArgumentException("Ключ не найден")
    }

    fun addKey(name: String, type: String, secret: String): KeyMeta {
        val key = requireUnlocked()
        val arr = readKeys()
        val id = System.currentTimeMillis().toString(36) + SecureRandom().nextInt(0xFFFF).toString(16)
        val (iv, ct) = encrypt(key, secret)
        val addedAt = System.currentTimeMillis()
        arr.put(JSONObject().apply {
            put("id", id); put("name", name); put("type", type)
            put("addedAt", addedAt); put("iv", iv); put("ct", ct)
        })
        prefs.edit().putString("keys", arr.toString()).apply()
        return KeyMeta(id, name, type, addedAt)
    }

    fun removeKey(id: String) {
        requireUnlocked()
        val arr = readKeys()
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            if (o.getString("id") != id) out.put(o)
        }
        prefs.edit().putString("keys", out.toString()).apply()
    }

    // ---- настройки ----
    fun isBiometricEnabled(): Boolean = prefs.getBoolean("bio_enabled", false)
    fun setBiometricBlob(ivB64: String, ctB64: String) {
        prefs.edit().putBoolean("bio_enabled", true)
            .putString("bio_iv", ivB64).putString("bio_ct", ctB64).apply()
    }
    fun clearBiometric() {
        prefs.edit().putBoolean("bio_enabled", false)
            .remove("bio_iv").remove("bio_ct").apply()
    }
    fun getBiometricBlob(): Pair<String, String>? {
        val iv = prefs.getString("bio_iv", null) ?: return null
        val ct = prefs.getString("bio_ct", null) ?: return null
        return iv to ct
    }
    fun isDisguised(): Boolean = prefs.getBoolean("disguised", false)
    fun setDisguised(v: Boolean) { prefs.edit().putBoolean("disguised", v).apply() }

    companion object {
        private const val VERIFIER = "selkorin-verify-v1"
    }
}
