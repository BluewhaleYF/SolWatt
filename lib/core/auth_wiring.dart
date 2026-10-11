import 'package:solar_network_foundation/solar_network_foundation.dart';

import 'package:solwatt/network.dart';
import 'package:solwatt/ui/alert.dart';

/// Binds the shared authentication surfaces (`solar_network_foundation`) to
/// SolWatt's authenticated client and alert helper.
///
/// The step-up elevation flow never reaches into app state directly: the host
/// owns the client it authenticates with and how an error is shown, exactly
/// the way the drive takes its client through an override.
///
/// The return type is inferred because Riverpod keeps `Override` out of its
/// public API surface, so it cannot be named here.
// ignore: strict_top_level_inference
authHostOverrides() {
  return [
    authClientProvider.overrideWith(
      (ref) => ref.watch(solarNetworkClientProvider),
    ),
    authErrorReporterProvider.overrideWithValue(showErrorAlert),
  ];
}
