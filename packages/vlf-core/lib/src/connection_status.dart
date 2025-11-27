enum VlfConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

extension VlfConnectionStatusX on VlfConnectionStatus {
  bool get isConnected => this == VlfConnectionStatus.connected;
  bool get isBusy => this == VlfConnectionStatus.connecting;
}
