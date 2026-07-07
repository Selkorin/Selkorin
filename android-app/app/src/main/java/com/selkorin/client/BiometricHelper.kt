package com.selkorin.client

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Разблокировка отпечатком/лицом: AES-ключ в Android Keystore привязан к
 * биометрии устройства (setUserAuthenticationRequired). Мастер-пароль
 * шифруется этим ключом один раз при включении и расшифровывается только
 * после успешной биометрической проверки.
 */
class BiometricHelper(private val activity: FragmentActivity) {

    companion object { private const val KEY_ALIAS = "selkorin_bio_key" }

    fun isSupported(): Boolean {
        val mgr = BiometricManager.from(activity)
        return mgr.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
            BiometricManager.BIOMETRIC_SUCCESS
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun getOrCreateKey(): SecretKey {
        val ks = keyStore()
        (ks.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val kg = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        kg.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .build()
        )
        return kg.generateKey()
    }

    /** Шифрует и сохраняет пароль ключом Keystore, привязанным к биометрии. */
    fun enable(password: String, vault: Vault, onResult: (Boolean, String?) -> Unit) {
        try {
            val key = getOrCreateKey()
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        try {
                            val c = result.cryptoObject?.cipher ?: return onResult(false, "Ошибка шифрования")
                            val ct = c.doFinal(password.toByteArray(Charsets.UTF_8))
                            vault.setBiometricBlob(
                                Base64.encodeToString(c.iv, Base64.NO_WRAP),
                                Base64.encodeToString(ct, Base64.NO_WRAP)
                            )
                            onResult(true, null)
                        } catch (e: Exception) { onResult(false, e.message) }
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        onResult(false, errString.toString())
                    }
                })
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Включить биометрию")
                .setSubtitle("Подтвердите отпечатком или лицом")
                .setNegativeButtonText("Отмена")
                .build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) { onResult(false, e.message) }
    }

    /** Разблокировать приложение биометрией: расшифровывает сохранённый пароль и юнлочит vault. */
    fun unlock(vault: Vault, onResult: (Boolean, String?) -> Unit) {
        val blob = vault.getBiometricBlob() ?: return onResult(false, "Биометрия не настроена")
        try {
            val key = keyStore().getKey(KEY_ALIAS, null) as? SecretKey
                ?: return onResult(false, "Ключ биометрии недоступен")
            val iv = Base64.decode(blob.first, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, iv))
            val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                        try {
                            val c = result.cryptoObject?.cipher ?: return onResult(false, "Ошибка")
                            val ct = Base64.decode(blob.second, Base64.NO_WRAP)
                            val password = String(c.doFinal(ct), Charsets.UTF_8)
                            onResult(vault.unlock(password), null)
                        } catch (e: Exception) { onResult(false, e.message) }
                    }
                    override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                        onResult(false, errString.toString())
                    }
                })
            val info = BiometricPrompt.PromptInfo.Builder()
                .setTitle("Разблокировать Selkorin")
                .setNegativeButtonText("Отмена")
                .build()
            prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (e: Exception) { onResult(false, e.message) }
    }

    fun disable(vault: Vault) { vault.clearBiometric() }
}

