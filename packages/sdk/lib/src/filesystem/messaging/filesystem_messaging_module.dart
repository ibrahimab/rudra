import 'package:rudra_communication/rudra_communication.dart';

import '../../messaging/application_request_context.dart';
import '../../messaging/application_request_handler_module.dart';

import 'list/codecs/filesystem_list_codecs.dart';
import 'list/filesystem_list_messages.dart';

/// Contributes filesystem application messaging capabilities.
///
/// Registers the typed representations used by host and client
/// filesystem communication.
///
/// Example:
/// ```dart
/// final registry = MessageCodecRegistry();
///
/// const FilesystemMessagingModule().register_codecs(registry);
///
/// registry.freeze();
/// ```
final class FilesystemMessagingModule
    implements ApplicationRequestHandlerModule {
  /// Creates the stateless filesystem messaging contribution.
  const FilesystemMessagingModule();

  /// Stable identity of the filesystem messaging contribution.
  @override
  String get module_id => 'rudra.filesystem.messaging';

  /// Contributes filesystem request and response codecs to [registry].
  ///
  /// The application composition boundary retains registry
  /// finalization and configuration ownership.
  ///
  /// Registry validation and registration failures propagate.
  @override
  void register_codecs(MessageCodecRegistry registry) {
    registry
      ..register_request<FilesystemListOpenResponse, FilesystemListOpenRequest>(
        const FilesystemListOpenRequestCodec(),
      )
      ..register_response<FilesystemListOpenResponse>(
        const FilesystemListOpenResponseCodec(),
      )
      ..register_request<
        FilesystemListBatchResponse,
        FilesystemListNextRequest
      >(const FilesystemListNextRequestCodec())
      ..register_response<FilesystemListBatchResponse>(
        const FilesystemListBatchResponseCodec(),
      )
      ..register_request<
        FilesystemListCancelResponse,
        FilesystemListCancelRequest
      >(const FilesystemListCancelRequestCodec())
      ..register_response<FilesystemListCancelResponse>(
        const FilesystemListCancelResponseCodec(),
      );
  }

  /// Contributes authoritative filesystem handlers to [registry].
  ///
  /// [context] supplies trusted peer authorization and the retained
  /// filesystem inspection owner.
  ///
  /// Every operation verifies its authenticated peer before accessing
  /// inspection admission, advancement or cancellation.
  ///
  /// Registration does not acquire inspection resources.
  @override
  void register_handlers(
    RequestHandlerRegistry registry,
    ApplicationRequestContext context,
  ) {
    registry
      ..register<FilesystemListOpenResponse, FilesystemListOpenRequest>((
        request,
        session,
      ) {
        context.require_authorized_peer(session);

        return context.filesystem_handlers.open(request, session);
      })
      ..register<FilesystemListBatchResponse, FilesystemListNextRequest>((
        request,
        session,
      ) {
        context.require_authorized_peer(session);

        return context.filesystem_handlers.next(request, session);
      })
      ..register<FilesystemListCancelResponse, FilesystemListCancelRequest>((
        request,
        session,
      ) {
        context.require_authorized_peer(session);

        return context.filesystem_handlers.cancel(request, session);
      });
  }
}
