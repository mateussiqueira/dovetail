abstract interface class DeepLinkInbox {
  Future<Uri?> initialLink();
  Stream<Uri> links();
}
