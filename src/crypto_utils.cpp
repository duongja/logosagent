#include "crypto_utils.h"

#include <QCryptographicHash>
#include <QFile>
#include <QJsonDocument>
#include <QRandomGenerator>

#include <openssl/evp.h>

namespace {

constexpr int AesGcmKeySize = 32;
constexpr int AesGcmNonceSize = 12;
constexpr int AesGcmTagSize = 16;
constexpr int Ed25519KeySize = 32;
constexpr int X25519KeySize = 32;

struct EvpCipherCtx
{
    EVP_CIPHER_CTX* ptr = EVP_CIPHER_CTX_new();
    ~EvpCipherCtx() { EVP_CIPHER_CTX_free(ptr); }
};

struct EvpPkey
{
    EVP_PKEY* ptr = nullptr;
    explicit EvpPkey(EVP_PKEY* key = nullptr) : ptr(key) {}
    ~EvpPkey() { EVP_PKEY_free(ptr); }
};

struct EvpPkeyCtx
{
    EVP_PKEY_CTX* ptr = nullptr;
    explicit EvpPkeyCtx(EVP_PKEY_CTX* ctx = nullptr) : ptr(ctx) {}
    ~EvpPkeyCtx() { EVP_PKEY_CTX_free(ptr); }
};

struct EvpMdCtx
{
    EVP_MD_CTX* ptr = EVP_MD_CTX_new();
    ~EvpMdCtx() { EVP_MD_CTX_free(ptr); }
};

QByteArray xorStream(const QByteArray& data, const QByteArray& key, const QByteArray& nonce)
{
    QByteArray out;
    out.resize(data.size());
    int offset = 0;
    quint64 counter = 0;
    while (offset < data.size()) {
        QByteArray blockInput = key + nonce + QByteArray::number(counter++);
        const QByteArray block = QCryptographicHash::hash(blockInput, QCryptographicHash::Sha256);
        for (int i = 0; i < block.size() && offset < data.size(); ++i, ++offset) {
            out[offset] = data[offset] ^ block[i];
        }
    }
    return out;
}

QByteArray canonicalObjectBytes(QJsonObject obj)
{
    obj.remove(QStringLiteral("signature"));
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

bool setCryptoError(QString* errorMessage, const QString& message)
{
    if (errorMessage) {
        *errorMessage = message;
    }
    return false;
}

QByteArray hmacSha256Bytes(QByteArray key, const QByteArray& data)
{
    const int blockSize = 64;
    if (key.size() > blockSize) {
        key = QCryptographicHash::hash(key, QCryptographicHash::Sha256);
    }
    QByteArray paddedKey(blockSize, char(0));
    for (int i = 0; i < key.size(); ++i) {
        paddedKey[i] = key[i];
    }
    QByteArray oKeyPad(blockSize, char(0x5c));
    QByteArray iKeyPad(blockSize, char(0x36));
    for (int i = 0; i < blockSize; ++i) {
        oKeyPad[i] = oKeyPad[i] ^ paddedKey[i];
        iKeyPad[i] = iKeyPad[i] ^ paddedKey[i];
    }
    const QByteArray inner = QCryptographicHash::hash(iKeyPad + data, QCryptographicHash::Sha256);
    return QCryptographicHash::hash(oKeyPad + inner, QCryptographicHash::Sha256);
}

QByteArray hkdfSha256(const QByteArray& inputKeyMaterial, const QByteArray& salt, const QByteArray& info, int outputSize)
{
    const QByteArray effectiveSalt = salt.isEmpty() ? QByteArray(32, char(0)) : salt;
    const QByteArray prk = hmacSha256Bytes(effectiveSalt, inputKeyMaterial);
    QByteArray okm;
    QByteArray previous;
    quint8 counter = 1;
    while (okm.size() < outputSize) {
        previous = hmacSha256Bytes(prk, previous + info + QByteArray(1, static_cast<char>(counter++)));
        okm.append(previous);
    }
    okm.resize(outputSize);
    return okm;
}

QByteArray aes256GcmEncrypt(const QByteArray& plain, const QByteArray& key, const QByteArray& nonce, QByteArray* tag, QString* errorMessage)
{
    if (key.size() != AesGcmKeySize || nonce.size() != AesGcmNonceSize || tag == nullptr) {
        setCryptoError(errorMessage, QStringLiteral("invalid AES-GCM key, nonce, or tag buffer"));
        return {};
    }

    EvpCipherCtx ctx;
    if (!ctx.ptr) {
        setCryptoError(errorMessage, QStringLiteral("failed to allocate AES-GCM context"));
        return {};
    }
    if (EVP_EncryptInit_ex(ctx.ptr, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) != 1
        || EVP_CIPHER_CTX_ctrl(ctx.ptr, EVP_CTRL_GCM_SET_IVLEN, nonce.size(), nullptr) != 1
        || EVP_EncryptInit_ex(ctx.ptr, nullptr, nullptr,
            reinterpret_cast<const unsigned char*>(key.constData()),
            reinterpret_cast<const unsigned char*>(nonce.constData())) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize AES-256-GCM encryption"));
        return {};
    }

    QByteArray cipher;
    cipher.resize(plain.size());
    int outLen = 0;
    int total = 0;
    if (!plain.isEmpty()) {
        if (EVP_EncryptUpdate(ctx.ptr,
                reinterpret_cast<unsigned char*>(cipher.data()),
                &outLen,
                reinterpret_cast<const unsigned char*>(plain.constData()),
                plain.size()) != 1) {
            setCryptoError(errorMessage, QStringLiteral("AES-256-GCM encryption failed"));
            return {};
        }
        total += outLen;
    }
    if (EVP_EncryptFinal_ex(ctx.ptr, reinterpret_cast<unsigned char*>(cipher.data()) + total, &outLen) != 1) {
        setCryptoError(errorMessage, QStringLiteral("AES-256-GCM finalization failed"));
        return {};
    }
    total += outLen;
    cipher.resize(total);

    tag->resize(AesGcmTagSize);
    if (EVP_CIPHER_CTX_ctrl(ctx.ptr, EVP_CTRL_GCM_GET_TAG, AesGcmTagSize, tag->data()) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to read AES-256-GCM tag"));
        return {};
    }
    return cipher;
}

QByteArray aes256GcmDecrypt(const QByteArray& cipher, const QByteArray& key, const QByteArray& nonce, const QByteArray& tag, QString* errorMessage)
{
    if (key.size() != AesGcmKeySize || nonce.size() != AesGcmNonceSize || tag.size() != AesGcmTagSize) {
        setCryptoError(errorMessage, QStringLiteral("invalid AES-GCM encryption metadata"));
        return {};
    }

    EvpCipherCtx ctx;
    if (!ctx.ptr) {
        setCryptoError(errorMessage, QStringLiteral("failed to allocate AES-GCM context"));
        return {};
    }
    if (EVP_DecryptInit_ex(ctx.ptr, EVP_aes_256_gcm(), nullptr, nullptr, nullptr) != 1
        || EVP_CIPHER_CTX_ctrl(ctx.ptr, EVP_CTRL_GCM_SET_IVLEN, nonce.size(), nullptr) != 1
        || EVP_DecryptInit_ex(ctx.ptr, nullptr, nullptr,
            reinterpret_cast<const unsigned char*>(key.constData()),
            reinterpret_cast<const unsigned char*>(nonce.constData())) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize AES-256-GCM decryption"));
        return {};
    }

    QByteArray plain;
    plain.resize(cipher.size());
    int outLen = 0;
    int total = 0;
    if (!cipher.isEmpty()) {
        if (EVP_DecryptUpdate(ctx.ptr,
                reinterpret_cast<unsigned char*>(plain.data()),
                &outLen,
                reinterpret_cast<const unsigned char*>(cipher.constData()),
                cipher.size()) != 1) {
            setCryptoError(errorMessage, QStringLiteral("AES-256-GCM decryption failed"));
            return {};
        }
        total += outLen;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx.ptr, EVP_CTRL_GCM_SET_TAG, tag.size(), const_cast<char*>(tag.constData())) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to set AES-256-GCM tag"));
        return {};
    }
    if (EVP_DecryptFinal_ex(ctx.ptr, reinterpret_cast<unsigned char*>(plain.data()) + total, &outLen) != 1) {
        setCryptoError(errorMessage, QStringLiteral("AES-256-GCM authentication failed"));
        return {};
    }
    total += outLen;
    plain.resize(total);
    return plain;
}

EvpPkey ed25519PrivateKeyFromSeed(const QByteArray& privateKey, QString* errorMessage)
{
    if (privateKey.size() != Ed25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("invalid Ed25519 private key length"));
        return EvpPkey();
    }
    EVP_PKEY* key = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_ED25519,
        nullptr,
        reinterpret_cast<const unsigned char*>(privateKey.constData()),
        privateKey.size());
    if (!key) {
        setCryptoError(errorMessage, QStringLiteral("failed to load Ed25519 private key"));
        return EvpPkey();
    }
    return EvpPkey(key);
}

EvpPkey ed25519PublicKeyFromBytes(const QByteArray& publicKey, QString* errorMessage)
{
    if (publicKey.size() != Ed25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("invalid Ed25519 public key length"));
        return EvpPkey();
    }
    EVP_PKEY* key = EVP_PKEY_new_raw_public_key(
        EVP_PKEY_ED25519,
        nullptr,
        reinterpret_cast<const unsigned char*>(publicKey.constData()),
        publicKey.size());
    if (!key) {
        setCryptoError(errorMessage, QStringLiteral("failed to load Ed25519 public key"));
        return EvpPkey();
    }
    return EvpPkey(key);
}

EvpPkey x25519PrivateKeyFromBytes(const QByteArray& privateKey, QString* errorMessage)
{
    if (privateKey.size() != X25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("invalid X25519 private key length"));
        return EvpPkey();
    }
    EVP_PKEY* key = EVP_PKEY_new_raw_private_key(
        EVP_PKEY_X25519,
        nullptr,
        reinterpret_cast<const unsigned char*>(privateKey.constData()),
        privateKey.size());
    if (!key) {
        setCryptoError(errorMessage, QStringLiteral("failed to load X25519 private key"));
        return EvpPkey();
    }
    return EvpPkey(key);
}

EvpPkey x25519PublicKeyFromBytes(const QByteArray& publicKey, QString* errorMessage)
{
    if (publicKey.size() != X25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("invalid X25519 public key length"));
        return EvpPkey();
    }
    EVP_PKEY* key = EVP_PKEY_new_raw_public_key(
        EVP_PKEY_X25519,
        nullptr,
        reinterpret_cast<const unsigned char*>(publicKey.constData()),
        publicKey.size());
    if (!key) {
        setCryptoError(errorMessage, QStringLiteral("failed to load X25519 public key"));
        return EvpPkey();
    }
    return EvpPkey(key);
}

QByteArray deriveX25519Secret(const QByteArray& privateKey, const QByteArray& peerPublicKey, QString* errorMessage)
{
    EvpPkey privatePkey = x25519PrivateKeyFromBytes(privateKey, errorMessage);
    if (!privatePkey.ptr) {
        return {};
    }
    EvpPkey peerPkey = x25519PublicKeyFromBytes(peerPublicKey, errorMessage);
    if (!peerPkey.ptr) {
        return {};
    }
    EvpPkeyCtx ctx(EVP_PKEY_CTX_new(privatePkey.ptr, nullptr));
    if (!ctx.ptr
        || EVP_PKEY_derive_init(ctx.ptr) != 1
        || EVP_PKEY_derive_set_peer(ctx.ptr, peerPkey.ptr) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize X25519 key agreement"));
        return {};
    }
    size_t secretLen = 0;
    if (EVP_PKEY_derive(ctx.ptr, nullptr, &secretLen) != 1 || secretLen == 0) {
        setCryptoError(errorMessage, QStringLiteral("failed to size X25519 shared secret"));
        return {};
    }
    QByteArray secret;
    secret.resize(static_cast<int>(secretLen));
    if (EVP_PKEY_derive(ctx.ptr, reinterpret_cast<unsigned char*>(secret.data()), &secretLen) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to derive X25519 shared secret"));
        return {};
    }
    secret.resize(static_cast<int>(secretLen));
    return secret;
}

QByteArray storageShareKek(const QByteArray& sharedSecret, const QByteArray& senderPublicKey, const QByteArray& recipientPublicKey)
{
    const QByteArray salt = senderPublicKey + recipientPublicKey;
    const QByteArray info("logos.storage.share.v1/x25519-hkdf-sha256-aes-256-gcm");
    return hkdfSha256(sharedSecret, salt, info, AesGcmKeySize);
}

} // namespace

namespace CryptoUtils {

QString randomId(const QString& prefix)
{
    const QByteArray bytes = randomBytes(16).toHex();
    if (prefix.isEmpty()) {
        return QString::fromLatin1(bytes);
    }
    return prefix + QStringLiteral("_") + QString::fromLatin1(bytes);
}

QString sha256Hex(const QByteArray& bytes)
{
    return QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}

QString hmacSha256Hex(const QByteArray& key, const QByteArray& data)
{
    return QString::fromLatin1(hmacSha256Bytes(key, data).toHex());
}

QByteArray randomBytes(int size)
{
    QByteArray out;
    out.resize(size);
    QRandomGenerator* rng = QRandomGenerator::system();
    for (int i = 0; i < size; ++i) {
        out[i] = static_cast<char>(rng->bounded(256));
    }
    return out;
}

QJsonObject encryptFile(const QString& inputPath, const QString& outputPath, QString* errorMessage)
{
    QFile in(inputPath);
    if (!in.open(QIODevice::ReadOnly)) {
        if (errorMessage) {
            *errorMessage = in.errorString();
        }
        return {};
    }
    const QByteArray plain = in.readAll();
    const QByteArray key = randomBytes(32);
    const QByteArray nonce = randomBytes(AesGcmNonceSize);
    QByteArray tag;
    const QByteArray cipher = aes256GcmEncrypt(plain, key, nonce, &tag, errorMessage);
    if (cipher.isEmpty() && !plain.isEmpty()) {
        return {};
    }
    QFile out(outputPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (errorMessage) {
            *errorMessage = out.errorString();
        }
        return {};
    }
    if (out.write(cipher) != cipher.size()) {
        if (errorMessage) {
            *errorMessage = out.errorString();
        }
        return {};
    }

    return QJsonObject{
        {QStringLiteral("alg"), QStringLiteral("aes-256-gcm")},
        {QStringLiteral("key_hex"), QString::fromLatin1(key.toHex())},
        {QStringLiteral("nonce_hex"), QString::fromLatin1(nonce.toHex())},
        {QStringLiteral("tag_hex"), QString::fromLatin1(tag.toHex())},
        {QStringLiteral("plain_sha256"), sha256Hex(plain)},
        {QStringLiteral("cipher_sha256"), sha256Hex(cipher)},
        {QStringLiteral("size"), static_cast<qint64>(plain.size())}
    };
}

bool decryptFile(const QString& inputPath, const QString& outputPath, const QJsonObject& encryption, QString* errorMessage)
{
    QFile in(inputPath);
    if (!in.open(QIODevice::ReadOnly)) {
        if (errorMessage) {
            *errorMessage = in.errorString();
        }
        return false;
    }
    const QByteArray cipher = in.readAll();
    const QString cipherHash = encryption.value(QStringLiteral("cipher_sha256")).toString();
    if (!cipherHash.isEmpty() && sha256Hex(cipher) != cipherHash) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("cipher content hash mismatch");
        }
        return false;
    }

    const QString alg = encryption.value(QStringLiteral("alg")).toString();
    const QByteArray key = QByteArray::fromHex(encryption.value(QStringLiteral("key_hex")).toString().toLatin1());
    const QByteArray nonce = QByteArray::fromHex(encryption.value(QStringLiteral("nonce_hex")).toString().toLatin1());
    QByteArray plain;
    if (alg == QStringLiteral("aes-256-gcm")) {
        const QByteArray tag = QByteArray::fromHex(encryption.value(QStringLiteral("tag_hex")).toString().toLatin1());
        plain = aes256GcmDecrypt(cipher, key, nonce, tag, errorMessage);
        if (plain.isEmpty() && !cipher.isEmpty()) {
            return false;
        }
    } else if (alg == QStringLiteral("xor-sha256-stream-dev")) {
        if (key.size() != 32 || nonce.size() != 16) {
            if (errorMessage) {
                *errorMessage = QStringLiteral("invalid legacy dev encryption metadata");
            }
            return false;
        }
        plain = xorStream(cipher, key, nonce);
    } else {
        if (errorMessage) {
            *errorMessage = QStringLiteral("unsupported encryption algorithm: %1").arg(alg);
        }
        return false;
    }
    const QString expectedHash = encryption.value(QStringLiteral("plain_sha256")).toString();
    if (!expectedHash.isEmpty() && sha256Hex(plain) != expectedHash) {
        if (errorMessage) {
            *errorMessage = QStringLiteral("decrypted content hash mismatch");
        }
        return false;
    }
    QFile out(outputPath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (errorMessage) {
            *errorMessage = out.errorString();
        }
        return false;
    }
    return out.write(plain) == plain.size();
}

QJsonObject generateEd25519KeyPair(QString* errorMessage)
{
    EvpPkeyCtx ctx(EVP_PKEY_CTX_new_id(EVP_PKEY_ED25519, nullptr));
    if (!ctx.ptr || EVP_PKEY_keygen_init(ctx.ptr) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize Ed25519 key generation"));
        return {};
    }

    EVP_PKEY* rawKey = nullptr;
    if (EVP_PKEY_keygen(ctx.ptr, &rawKey) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to generate Ed25519 key pair"));
        return {};
    }
    EvpPkey key(rawKey);

    QByteArray privateKey;
    privateKey.resize(Ed25519KeySize);
    size_t privateLen = privateKey.size();
    if (EVP_PKEY_get_raw_private_key(key.ptr, reinterpret_cast<unsigned char*>(privateKey.data()), &privateLen) != 1
        || privateLen != Ed25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("failed to export Ed25519 private key"));
        return {};
    }

    QByteArray publicKey;
    publicKey.resize(Ed25519KeySize);
    size_t publicLen = publicKey.size();
    if (EVP_PKEY_get_raw_public_key(key.ptr, reinterpret_cast<unsigned char*>(publicKey.data()), &publicLen) != 1
        || publicLen != Ed25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("failed to export Ed25519 public key"));
        return {};
    }

    return QJsonObject{
        {QStringLiteral("type"), QStringLiteral("ed25519")},
        {QStringLiteral("public_key_hex"), QString::fromLatin1(publicKey.toHex())},
        {QStringLiteral("private_key_hex"), QString::fromLatin1(privateKey.toHex())},
        {QStringLiteral("key_id"), ed25519KeyId(QString::fromLatin1(publicKey.toHex()))}
    };
}

QString ed25519KeyId(const QString& publicKeyHex)
{
    const QByteArray publicKey = QByteArray::fromHex(publicKeyHex.toLatin1());
    if (publicKey.size() != Ed25519KeySize) {
        return {};
    }
    return QStringLiteral("ed25519:%1").arg(sha256Hex(publicKey).left(32));
}

QString signObjectEd25519(const QJsonObject& obj, const QString& privateKeyHex, QString* errorMessage)
{
    const QByteArray privateKey = QByteArray::fromHex(privateKeyHex.toLatin1());
    EvpPkey key = ed25519PrivateKeyFromSeed(privateKey, errorMessage);
    if (!key.ptr) {
        return {};
    }

    const QByteArray data = canonicalObjectBytes(obj);
    EvpMdCtx ctx;
    if (!ctx.ptr || EVP_DigestSignInit(ctx.ptr, nullptr, nullptr, nullptr, key.ptr) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize Ed25519 signing"));
        return {};
    }

    size_t sigLen = 0;
    if (EVP_DigestSign(ctx.ptr, nullptr, &sigLen,
            reinterpret_cast<const unsigned char*>(data.constData()),
            data.size()) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to size Ed25519 signature"));
        return {};
    }

    QByteArray signature;
    signature.resize(static_cast<int>(sigLen));
    if (EVP_DigestSign(ctx.ptr,
            reinterpret_cast<unsigned char*>(signature.data()),
            &sigLen,
            reinterpret_cast<const unsigned char*>(data.constData()),
            data.size()) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to create Ed25519 signature"));
        return {};
    }
    signature.resize(static_cast<int>(sigLen));
    return QString::fromLatin1(signature.toHex());
}

bool verifyObjectSignatureEd25519(const QJsonObject& obj, const QString& publicKeyHex, const QString& signatureHex)
{
    const QByteArray publicKey = QByteArray::fromHex(publicKeyHex.toLatin1());
    const QByteArray signature = QByteArray::fromHex(signatureHex.toLatin1());
    QString err;
    EvpPkey key = ed25519PublicKeyFromBytes(publicKey, &err);
    if (!key.ptr || signature.isEmpty()) {
        return false;
    }

    const QByteArray data = canonicalObjectBytes(obj);
    EvpMdCtx ctx;
    if (!ctx.ptr || EVP_DigestVerifyInit(ctx.ptr, nullptr, nullptr, nullptr, key.ptr) != 1) {
        return false;
    }
    return EVP_DigestVerify(ctx.ptr,
        reinterpret_cast<const unsigned char*>(signature.constData()),
        signature.size(),
        reinterpret_cast<const unsigned char*>(data.constData()),
        data.size()) == 1;
}

QJsonObject generateX25519KeyPair(QString* errorMessage)
{
    EvpPkeyCtx ctx(EVP_PKEY_CTX_new_id(EVP_PKEY_X25519, nullptr));
    if (!ctx.ptr || EVP_PKEY_keygen_init(ctx.ptr) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to initialize X25519 key generation"));
        return {};
    }

    EVP_PKEY* rawKey = nullptr;
    if (EVP_PKEY_keygen(ctx.ptr, &rawKey) != 1) {
        setCryptoError(errorMessage, QStringLiteral("failed to generate X25519 key pair"));
        return {};
    }
    EvpPkey key(rawKey);

    QByteArray privateKey;
    privateKey.resize(X25519KeySize);
    size_t privateLen = privateKey.size();
    if (EVP_PKEY_get_raw_private_key(key.ptr, reinterpret_cast<unsigned char*>(privateKey.data()), &privateLen) != 1
        || privateLen != X25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("failed to export X25519 private key"));
        return {};
    }

    QByteArray publicKey;
    publicKey.resize(X25519KeySize);
    size_t publicLen = publicKey.size();
    if (EVP_PKEY_get_raw_public_key(key.ptr, reinterpret_cast<unsigned char*>(publicKey.data()), &publicLen) != 1
        || publicLen != X25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("failed to export X25519 public key"));
        return {};
    }

    return QJsonObject{
        {QStringLiteral("type"), QStringLiteral("x25519")},
        {QStringLiteral("public_key_hex"), QString::fromLatin1(publicKey.toHex())},
        {QStringLiteral("private_key_hex"), QString::fromLatin1(privateKey.toHex())},
        {QStringLiteral("key_id"), x25519KeyId(QString::fromLatin1(publicKey.toHex()))}
    };
}

QString x25519KeyId(const QString& publicKeyHex)
{
    const QByteArray publicKey = QByteArray::fromHex(publicKeyHex.toLatin1());
    if (publicKey.size() != X25519KeySize) {
        return {};
    }
    return QStringLiteral("x25519:%1").arg(sha256Hex(publicKey).left(32));
}

QJsonObject wrapEncryptionForRecipient(const QJsonObject& encryption, const QString& recipientPublicKeyHex, QString* errorMessage)
{
    const QByteArray fileKey = QByteArray::fromHex(encryption.value(QStringLiteral("key_hex")).toString().toLatin1());
    const QByteArray recipientPublicKey = QByteArray::fromHex(recipientPublicKeyHex.toLatin1());
    if (fileKey.size() != AesGcmKeySize) {
        setCryptoError(errorMessage, QStringLiteral("storage encryption metadata does not contain a valid AES-256 key"));
        return {};
    }
    if (recipientPublicKey.size() != X25519KeySize) {
        setCryptoError(errorMessage, QStringLiteral("recipient encryption public key must be a 32-byte X25519 key"));
        return {};
    }

    QString keyErr;
    const QJsonObject ephemeral = generateX25519KeyPair(&keyErr);
    if (!keyErr.isEmpty()) {
        setCryptoError(errorMessage, keyErr);
        return {};
    }
    const QByteArray ephemeralPrivateKey = QByteArray::fromHex(ephemeral.value(QStringLiteral("private_key_hex")).toString().toLatin1());
    const QByteArray ephemeralPublicKey = QByteArray::fromHex(ephemeral.value(QStringLiteral("public_key_hex")).toString().toLatin1());
    const QByteArray sharedSecret = deriveX25519Secret(ephemeralPrivateKey, recipientPublicKey, errorMessage);
    if (sharedSecret.isEmpty()) {
        return {};
    }

    const QByteArray kek = storageShareKek(sharedSecret, ephemeralPublicKey, recipientPublicKey);
    const QByteArray wrapNonce = randomBytes(AesGcmNonceSize);
    QByteArray wrapTag;
    const QByteArray wrappedKey = aes256GcmEncrypt(fileKey, kek, wrapNonce, &wrapTag, errorMessage);
    if (wrappedKey.isEmpty()) {
        return {};
    }

    QJsonObject out = encryption;
    out.remove(QStringLiteral("key_hex"));
    out.insert(QStringLiteral("key_wrap"), QJsonObject{
        {QStringLiteral("alg"), QStringLiteral("x25519-hkdf-sha256-aes-256-gcm")},
        {QStringLiteral("recipient_key_id"), x25519KeyId(recipientPublicKeyHex)},
        {QStringLiteral("recipient_public_key_hex"), recipientPublicKeyHex},
        {QStringLiteral("sender_ephemeral_public_key_hex"), QString::fromLatin1(ephemeralPublicKey.toHex())},
        {QStringLiteral("wrap_nonce_hex"), QString::fromLatin1(wrapNonce.toHex())},
        {QStringLiteral("wrapped_key_hex"), QString::fromLatin1(wrappedKey.toHex())},
        {QStringLiteral("wrap_tag_hex"), QString::fromLatin1(wrapTag.toHex())}
    });
    return out;
}

QJsonObject unwrapEncryptionForRecipient(const QJsonObject& wrappedEncryption, const QJsonObject& recipientIdentity, QString* errorMessage)
{
    const QJsonObject keyWrap = wrappedEncryption.value(QStringLiteral("key_wrap")).toObject();
    if (keyWrap.value(QStringLiteral("alg")).toString() != QStringLiteral("x25519-hkdf-sha256-aes-256-gcm")) {
        setCryptoError(errorMessage, QStringLiteral("unsupported storage key wrap algorithm"));
        return {};
    }

    const QString recipientPublicKeyHex = keyWrap.value(QStringLiteral("recipient_public_key_hex")).toString(
        recipientIdentity.value(QStringLiteral("public_key_hex")).toString());
    const QByteArray recipientPublicKey = QByteArray::fromHex(recipientPublicKeyHex.toLatin1());
    const QByteArray recipientPrivateKey = QByteArray::fromHex(recipientIdentity.value(QStringLiteral("private_key_hex")).toString().toLatin1());
    const QByteArray senderEphemeralPublicKey = QByteArray::fromHex(keyWrap.value(QStringLiteral("sender_ephemeral_public_key_hex")).toString().toLatin1());
    const QByteArray wrappedKey = QByteArray::fromHex(keyWrap.value(QStringLiteral("wrapped_key_hex")).toString().toLatin1());
    const QByteArray wrapNonce = QByteArray::fromHex(keyWrap.value(QStringLiteral("wrap_nonce_hex")).toString().toLatin1());
    const QByteArray wrapTag = QByteArray::fromHex(keyWrap.value(QStringLiteral("wrap_tag_hex")).toString().toLatin1());
    if (recipientPublicKey.size() != X25519KeySize
        || recipientPrivateKey.size() != X25519KeySize
        || senderEphemeralPublicKey.size() != X25519KeySize
        || wrappedKey.isEmpty()
        || wrapNonce.size() != AesGcmNonceSize
        || wrapTag.size() != AesGcmTagSize) {
        setCryptoError(errorMessage, QStringLiteral("invalid wrapped storage encryption metadata"));
        return {};
    }

    const QString expectedKeyId = keyWrap.value(QStringLiteral("recipient_key_id")).toString();
    if (!expectedKeyId.isEmpty() && expectedKeyId != x25519KeyId(recipientPublicKeyHex)) {
        setCryptoError(errorMessage, QStringLiteral("storage key wrap recipient key id mismatch"));
        return {};
    }
    const QString localKeyId = recipientIdentity.value(QStringLiteral("key_id")).toString();
    if (!localKeyId.isEmpty() && localKeyId != x25519KeyId(recipientPublicKeyHex)) {
        setCryptoError(errorMessage, QStringLiteral("storage key wrap is not addressed to this agent encryption key"));
        return {};
    }

    const QByteArray sharedSecret = deriveX25519Secret(recipientPrivateKey, senderEphemeralPublicKey, errorMessage);
    if (sharedSecret.isEmpty()) {
        return {};
    }
    const QByteArray kek = storageShareKek(sharedSecret, senderEphemeralPublicKey, recipientPublicKey);
    const QByteArray fileKey = aes256GcmDecrypt(wrappedKey, kek, wrapNonce, wrapTag, errorMessage);
    if (fileKey.size() != AesGcmKeySize) {
        if (errorMessage && errorMessage->isEmpty()) {
            *errorMessage = QStringLiteral("unwrapped storage key has invalid length");
        }
        return {};
    }

    QJsonObject out = wrappedEncryption;
    out.remove(QStringLiteral("key_wrap"));
    out.insert(QStringLiteral("key_hex"), QString::fromLatin1(fileKey.toHex()));
    return out;
}

QString signObject(const QJsonObject& obj, const QString& secret)
{
    return hmacSha256Hex(secret.toUtf8(), canonicalObjectBytes(obj));
}

bool verifyObjectSignature(const QJsonObject& obj, const QString& secret, const QString& signature)
{
    return !signature.isEmpty() && signObject(obj, secret) == signature;
}

} // namespace CryptoUtils
