package app.lume.personal

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val secrets = SecureSecrets(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "app.lume.personal/secure_secrets",
        ).setMethodCallHandler { call, result ->
            try {
                val key = call.argument<String>("key")
                if (!isValidSecretKey(key)) {
                    result.error("bad-arguments", "Invalid secret key.", null)
                    return@setMethodCallHandler
                }

                when (call.method) {
                    "read" -> result.success(secrets.read(key!!))
                    "write" -> {
                        val value = call.argument<String>("value").orEmpty()
                        if (value.isEmpty()) {
                            secrets.delete(key!!)
                        } else {
                            secrets.write(key!!, value)
                        }
                        result.success(null)
                    }
                    "delete" -> {
                        secrets.delete(key!!)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("secure-secret-error", "Secure storage unavailable.", null)
            }
        }
    }

    private fun isValidSecretKey(key: String?): Boolean {
        return key != null && secretKeyPattern.matches(key)
    }

    companion object {
        private val secretKeyPattern = Regex("[A-Za-z0-9._-]{1,64}")
    }
}

private class SecureSecrets(context: Context) {
    private val preferences = context.getSharedPreferences(
        "lume_secure_secrets",
        Context.MODE_PRIVATE,
    )

    fun read(key: String): String? {
        val packed = preferences.getString(key, null) ?: return null
        return try {
            val decoded = Base64.decode(packed, Base64.NO_WRAP)
            val buffer = ByteBuffer.wrap(decoded)
            val ivLength = buffer.int
            if (ivLength <= 0 || ivLength > decoded.size) {
                delete(key)
                return null
            }
            val iv = ByteArray(ivLength)
            buffer.get(iv)
            val cipherText = ByteArray(buffer.remaining())
            buffer.get(cipherText)

            val cipher = Cipher.getInstance(transformation)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(gcmTagBits, iv))
            String(cipher.doFinal(cipherText), Charsets.UTF_8)
        } catch (_: Exception) {
            delete(key)
            null
        }
    }

    fun write(key: String, value: String) {
        val cipher = Cipher.getInstance(transformation)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val cipherText = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val iv = cipher.iv
        val packed = ByteBuffer.allocate(Int.SIZE_BYTES + iv.size + cipherText.size)
            .putInt(iv.size)
            .put(iv)
            .put(cipherText)
            .array()

        preferences.edit()
            .putString(key, Base64.encodeToString(packed, Base64.NO_WRAP))
            .commit()
            .also { saved ->
                if (!saved) {
                    throw IllegalStateException("Secure secret write failed.")
                }
            }
    }

    fun delete(key: String) {
        preferences.edit()
            .remove(key)
            .commit()
            .also { saved ->
                if (!saved) {
                    throw IllegalStateException("Secure secret delete failed.")
                }
            }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply {
            load(null)
        }
        val existing = keyStore.getEntry(keyAlias, null) as? KeyStore.SecretKeyEntry
        if (existing != null) {
            return existing.secretKey
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true)
            .build()
        generator.init(spec)
        return generator.generateKey()
    }

    companion object {
        private const val keyAlias = "lume_secure_secrets_aes"
        private const val transformation = "AES/GCM/NoPadding"
        private const val gcmTagBits = 128
    }
}
