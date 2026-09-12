/**
 * Calculates the distance between two GPS coordinates in meters using the Haversine formula.
 */
export function calculateDistanceMeters(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const R = 6371e3; // Earth's radius in meters
  const phi1 = (lat1 * Math.PI) / 180;
  const phi2 = (lat2 * Math.PI) / 180;
  const deltaPhi = ((lat2 - lat1) * Math.PI) / 180;
  const deltaLambda = ((lon2 - lon1) * Math.PI) / 180;

  const a =
    Math.sin(deltaPhi / 2) * Math.sin(deltaPhi / 2) +
    Math.cos(phi1) * Math.cos(phi2) *
    Math.sin(deltaLambda / 2) * Math.sin(deltaLambda / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}

export interface GeofenceConfig {
  lat: number;
  lng: number;
  radius_meters: number;
  enabled: boolean;
}

/**
 * Checks if the telemetry coordinate has breached the geofence boundary.
 */
export function isGeofenceBreached(
  currentLat: number,
  currentLng: number,
  config: GeofenceConfig
): boolean {
  if (!config.enabled) return false;
  
  const distance = calculateDistanceMeters(
    currentLat,
    currentLng,
    config.lat,
    config.lng
  );
  
  return distance > config.radius_meters;
}
