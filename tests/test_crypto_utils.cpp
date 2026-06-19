#include <logos_test.h>

#include "crypto_utils.h"

#include <QDir>
#include <QFile>
#include <QJsonObject>

namespace {

QString testPath(const QString& name)
{
    const QString dir = QDir::tempPath() + QStringLiteral("/logos-agent-crypto-tests");
    QDir().mkpath(dir);
    return dir + QStringLiteral("/") + name;
}

QByteArray readAll(const QString& path)
{
    QFile file(path);
    LOGOS_ASSERT_TRUE(file.open(QIODevice::ReadOnly));
    return file.readAll();
}

void writeAll(const QString& path, const QByteArray& bytes)
{
    QFile file(path);
    LOGOS_ASSERT_TRUE(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    LOGOS_ASSERT_EQ(file.write(bytes), bytes.size());
}

} // namespace

LOGOS_TEST(aes_gcm_file_encryption_round_trips)
{
    const QString plainPath = testPath(QStringLiteral("plain.txt"));
    const QString cipherPath = testPath(QStringLiteral("cipher.bin"));
    const QString restoredPath = testPath(QStringLiteral("restored.txt"));
    const QByteArray plain("logos storage encryption test payload");
    writeAll(plainPath, plain);

    QString err;
    const QJsonObject metadata = CryptoUtils::encryptFile(plainPath, cipherPath, &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_EQ(metadata.value(QStringLiteral("alg")).toString().toStdString(), std::string("aes-256-gcm"));
    LOGOS_ASSERT_TRUE(metadata.contains(QStringLiteral("tag_hex")));
    LOGOS_ASSERT_TRUE(readAll(cipherPath) != plain);

    LOGOS_ASSERT_TRUE(CryptoUtils::decryptFile(cipherPath, restoredPath, metadata, &err));
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_EQ(readAll(restoredPath).toStdString(), plain.toStdString());
}

LOGOS_TEST(aes_gcm_file_encryption_rejects_tampering)
{
    const QString plainPath = testPath(QStringLiteral("tamper-plain.txt"));
    const QString cipherPath = testPath(QStringLiteral("tamper-cipher.bin"));
    const QString restoredPath = testPath(QStringLiteral("tamper-restored.txt"));
    writeAll(plainPath, QByteArray("payload that will be tampered"));

    QString err;
    const QJsonObject metadata = CryptoUtils::encryptFile(plainPath, cipherPath, &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());

    QByteArray cipher = readAll(cipherPath);
    cipher[0] = cipher[0] ^ char(0x01);
    writeAll(cipherPath, cipher);

    LOGOS_ASSERT_FALSE(CryptoUtils::decryptFile(cipherPath, restoredPath, metadata, &err));
    LOGOS_ASSERT_FALSE(err.isEmpty());
}

LOGOS_TEST(ed25519_signatures_verify_and_reject_tampering)
{
    QString err;
    const QJsonObject keyPair = CryptoUtils::generateEd25519KeyPair(&err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_EQ(keyPair.value(QStringLiteral("type")).toString().toStdString(), std::string("ed25519"));
    LOGOS_ASSERT_FALSE(keyPair.value(QStringLiteral("public_key_hex")).toString().isEmpty());
    LOGOS_ASSERT_FALSE(keyPair.value(QStringLiteral("private_key_hex")).toString().isEmpty());

    QJsonObject payload{
        {QStringLiteral("kind"), QStringLiteral("task.submit")},
        {QStringLiteral("nonce"), QStringLiteral("msg_1")},
        {QStringLiteral("payload"), QJsonObject{{QStringLiteral("skill"), QStringLiteral("storage.upload")}}}
    };
    const QString signature = CryptoUtils::signObjectEd25519(payload, keyPair.value(QStringLiteral("private_key_hex")).toString(), &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_FALSE(signature.isEmpty());

    payload.insert(QStringLiteral("signature"), signature);
    LOGOS_ASSERT_TRUE(CryptoUtils::verifyObjectSignatureEd25519(payload, keyPair.value(QStringLiteral("public_key_hex")).toString(), signature));

    QJsonObject tampered = payload;
    tampered.insert(QStringLiteral("kind"), QStringLiteral("task.cancel"));
    LOGOS_ASSERT_FALSE(CryptoUtils::verifyObjectSignatureEd25519(tampered, keyPair.value(QStringLiteral("public_key_hex")).toString(), signature));
}

LOGOS_TEST(x25519_storage_key_wrap_round_trips)
{
    QString err;
    const QJsonObject recipient = CryptoUtils::generateX25519KeyPair(&err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_EQ(recipient.value(QStringLiteral("type")).toString().toStdString(), std::string("x25519"));

    const QJsonObject encryption{
        {QStringLiteral("alg"), QStringLiteral("aes-256-gcm")},
        {QStringLiteral("key_hex"), QStringLiteral("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")},
        {QStringLiteral("nonce_hex"), QStringLiteral("aaaaaaaaaaaaaaaaaaaaaaaa")},
        {QStringLiteral("tag_hex"), QStringLiteral("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")},
        {QStringLiteral("plain_sha256"), QStringLiteral("plain")},
        {QStringLiteral("cipher_sha256"), QStringLiteral("cipher")},
    };

    const QJsonObject wrapped = CryptoUtils::wrapEncryptionForRecipient(
        encryption,
        recipient.value(QStringLiteral("public_key_hex")).toString(),
        &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_FALSE(wrapped.contains(QStringLiteral("key_hex")));
    LOGOS_ASSERT_TRUE(wrapped.value(QStringLiteral("key_wrap")).isObject());

    const QJsonObject unwrapped = CryptoUtils::unwrapEncryptionForRecipient(wrapped, recipient, &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    LOGOS_ASSERT_EQ(
        unwrapped.value(QStringLiteral("key_hex")).toString().toStdString(),
        encryption.value(QStringLiteral("key_hex")).toString().toStdString());
}

LOGOS_TEST(x25519_storage_key_wrap_rejects_wrong_recipient)
{
    QString err;
    const QJsonObject recipient = CryptoUtils::generateX25519KeyPair(&err);
    LOGOS_ASSERT_TRUE(err.isEmpty());
    const QJsonObject wrongRecipient = CryptoUtils::generateX25519KeyPair(&err);
    LOGOS_ASSERT_TRUE(err.isEmpty());

    const QJsonObject encryption{
        {QStringLiteral("alg"), QStringLiteral("aes-256-gcm")},
        {QStringLiteral("key_hex"), QStringLiteral("202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f")},
        {QStringLiteral("nonce_hex"), QStringLiteral("cccccccccccccccccccccccc")},
        {QStringLiteral("tag_hex"), QStringLiteral("dddddddddddddddddddddddddddddddd")},
    };
    const QJsonObject wrapped = CryptoUtils::wrapEncryptionForRecipient(
        encryption,
        recipient.value(QStringLiteral("public_key_hex")).toString(),
        &err);
    LOGOS_ASSERT_TRUE(err.isEmpty());

    const QJsonObject unwrapped = CryptoUtils::unwrapEncryptionForRecipient(wrapped, wrongRecipient, &err);
    LOGOS_ASSERT_TRUE(unwrapped.isEmpty());
    LOGOS_ASSERT_FALSE(err.isEmpty());
}
