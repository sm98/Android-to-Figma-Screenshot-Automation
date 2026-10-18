package com.sanoop.screenshotsync.pairing

import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.X509TrustManager

/**
 * Trusts exactly one certificate: the one whose whole-certificate SHA-256 fingerprint matches
 * what was scanned from the Mac's pairing QR. No system CA trust store is consulted — this
 * mirrors the Mac side's self-signed identity (there is no CA in this protocol at all).
 */
class PinnedTrustManager(private val expectedFingerprintHex: String) : X509TrustManager {

    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        throw CertificateException("Client certificates are not used by this app")
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
        val leaf = chain?.firstOrNull() ?: throw CertificateException("No certificate presented")
        val digest = MessageDigest.getInstance("SHA-256").digest(leaf.encoded)
        val hex = digest.joinToString("") { "%02x".format(it) }
        if (!hex.equals(expectedFingerprintHex, ignoreCase = true)) {
            throw CertificateException("Certificate fingerprint mismatch: expected $expectedFingerprintHex, got $hex")
        }
    }

    override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()

    fun buildSocketFactory(): SSLSocketFactory {
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf(this), SecureRandom())
        return sslContext.socketFactory
    }
}
