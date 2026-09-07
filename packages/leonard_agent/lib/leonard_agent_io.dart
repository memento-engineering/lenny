/// I/O-only harness entrypoint for hosts that create VM-service connections.
///
/// This re-exports the web-safe `leonard_agent.dart` API and adds the owning
/// connection functions used by command-line and native hosts. Web consumers
/// should continue to import `leonard_agent.dart` and supply a borrowed
/// `VmService` connection.
library;

export 'leonard_agent.dart';
export 'src/vm_service_client_io.dart'
    show connectLeonardSession, connectMultiHostSession, connectVmServiceClient;
