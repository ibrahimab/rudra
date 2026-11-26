import 'dart:io';
import 'dart:typed_data';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';

/// Darwin socket-option level for Unix-domain sockets.
const int _sol_local = 0;

/// Darwin socket option for retrieving connected peer credentials.
const int _local_peercred = 0x001;

/// Supported Darwin external credential structure version.
const int _xucred_version = 0;

/// Size of Darwin's external credential structure in bytes.
///
/// Applies to supported 64-bit macOS architectures.
const int _xucred_size = 76;

/// Byte offset of the credential structure version.
const int _version_offset = 0;

/// Byte offset of the effective operating-system UID.
const int _uid_offset = 4;

/// Byte offset of the advisory group count.
const int _group_count_offset = 8;

/// Maximum advisory groups represented by the Darwin structure.
const int _maximum_group_count = 16;

/// Reserved unsigned UID value representing an invalid identity.
const int _invalid_uid = 0xffffffff;

/// Reads trusted peer credentials from connected Darwin sockets.
///
/// Retrieves the effective operating-system user identity
/// established by the kernel during Unix-domain connection
/// establishment.
///
/// The resulting identity uses the macOS effective-UID namespace,
/// allowing consumers to compare authenticated peers against
/// an independently established trusted owner.
///
/// Socket ownership remains with the caller.
///
/// Example:
/// ```dart
/// final credentials = DarwinPeerCredentials();
///
/// final os_user_id = credentials.read_os_user_id(socket);
///
/// print(os_user_id);
/// // Example: macos-uid:501
/// ```
final class DarwinPeerCredentials {
  /// Creates a Darwin peer credential reader.
  ///
  /// Native credential retrieval is deferred until
  /// [read_os_user_id] is invoked.
  const DarwinPeerCredentials();

  /// Resolves the effective identity of the connected [socket] peer.
  ///
  /// [socket] must represent an established Unix-domain connection.
  ///
  /// Returns the kernel-provided UID within Rudra's macOS
  /// operating-system identity namespace.
  ///
  /// Throws [UnsupportedError] outside macOS, [ArgumentError]
  /// for unsupported socket families, or [StateError] when
  /// the returned credential structure is invalid.
  ///
  /// Native socket-option failures propagate to the caller.
  String read_os_user_id(Socket socket) {
    if (!Platform.isMacOS) {
      throw UnsupportedError('Darwin peer credentials require macOS.');
    }

    // Socket-option numbers have different meanings across
    // protocol families. Only Unix-domain sockets are accepted.
    if (socket.address.type != InternetAddressType.unix) {
      throw ArgumentError('Peer credentials require a Unix-domain socket.');
    }

    // Initialize the buffer with an invalid value so an unwritten
    // credential structure cannot be mistaken for UID zero.
    final buffer = Uint8List(_xucred_size)..fillRange(0, _xucred_size, 0xff);

    // Retrieve credentials directly from the kernel without
    // accepting identity information from the remote process.
    final credentials = socket.getRawOption(
      RawSocketOption(_sol_local, _local_peercred, buffer),
    );

    if (credentials.length != _xucred_size) {
      throw StateError('Unexpected Darwin peer credential structure size.');
    }

    final data = ByteData.sublistView(credentials);

    // Darwin exposes the credential structure using the native
    // machine byte order rather than network byte order.
    final version = data.getUint32(_version_offset, Endian.host);

    if (version != _xucred_version) {
      throw StateError('Unsupported Darwin peer credential version: $version.');
    }

    final uid = data.getUint32(_uid_offset, Endian.host);

    final group_count = data.getInt16(_group_count_offset, Endian.host);

    // Validate the relevant credential fields before constructing
    // an identity that could be used for host authorization.
    if (uid == _invalid_uid ||
        group_count < 1 ||
        group_count > _maximum_group_count) {
      throw StateError('Invalid Darwin peer credential structure.');
    }

    return macos_user_id(uid);
  }
}
