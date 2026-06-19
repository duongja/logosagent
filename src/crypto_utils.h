#ifndef LOGOS_AGENT_CRYPTO_UTILS_H
#define LOGOS_AGENT_CRYPTO_UTILS_H

#include <QByteArray>
#include <QJsonObject>
#include <QString>

namespace CryptoUtils {

QString randomId(const QString& prefix = QString());
QString sha256Hex(const QByteArray& bytes);
QString hmacSha256Hex(const QByteArray& key, const QByteArray& data);
QByteArray randomBytes(int size);

QJsonObject encryptFile(const QString& inputPath, const QString& outputPath, QString* errorMessage = nullptr);
bool decryptFile(const QString& inputPath, const QString& outputPath, const QJsonObject& encryption, QString* errorMessage = nullptr);

QJsonObject generateEd25519KeyPair(QString* errorMessage = nullptr);
QString ed25519KeyId(const QString& publicKeyHex);
QString signObjectEd25519(const QJsonObject& obj, const QString& privateKeyHex, QString* errorMessage = nullptr);
bool verifyObjectSignatureEd25519(const QJsonObject& obj, const QString& publicKeyHex, const QString& signatureHex);

QJsonObject generateX25519KeyPair(QString* errorMessage = nullptr);
QString x25519KeyId(const QString& publicKeyHex);
QJsonObject wrapEncryptionForRecipient(const QJsonObject& encryption, const QString& recipientPublicKeyHex, QString* errorMessage = nullptr);
QJsonObject unwrapEncryptionForRecipient(const QJsonObject& wrappedEncryption, const QJsonObject& recipientIdentity, QString* errorMessage = nullptr);

QString signObject(const QJsonObject& obj, const QString& secret);
bool verifyObjectSignature(const QJsonObject& obj, const QString& secret, const QString& signature);

} // namespace CryptoUtils

#endif
