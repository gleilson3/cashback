import type { StoreLocation } from '../types';
import { STORE_LOCATIONS } from '../types';

export function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371e3; // Earth's radius in meters
  const φ1 = lat1 * Math.PI / 180;
  const φ2 = lat2 * Math.PI / 180;
  const Δφ = (lat2 - lat1) * Math.PI / 180;
  const Δλ = (lon2 - lon1) * Math.PI / 180;

  const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
    Math.cos(φ1) * Math.cos(φ2) *
    Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c; // Distance in meters
}

export async function getCurrentPosition(): Promise<GeolocationPosition> {
  if (!navigator.geolocation) {
    throw new Error('Seu navegador não suporta geolocalização');
  }

  // First check if permissions are granted
  try {
    const permissionStatus = await navigator.permissions.query({ name: 'geolocation' });
    if (permissionStatus.state === 'denied') {
      throw new Error('Por favor, permita o acesso à sua localização nas configurações do seu navegador e tente novamente.');
    }
  } catch (error) {
    // If permissions API is not supported, continue with regular geolocation
    console.warn('Permissions API not supported, falling back to regular geolocation');
  }

  return new Promise((resolve, reject) => {
    const timeoutId = setTimeout(() => {
      reject(new Error('Tempo esgotado ao tentar obter sua localização. Por favor, verifique se o GPS está ativado e tente novamente.'));
    }, 15000); // 15 second timeout

    const options = {
      enableHighAccuracy: true,
      timeout: 15000,
      maximumAge: 0
    };

    navigator.geolocation.getCurrentPosition(
      (position) => {
        clearTimeout(timeoutId);
        resolve(position);
      },
      (error) => {
        clearTimeout(timeoutId);
        switch (error.code) {
          case error.PERMISSION_DENIED:
            reject(new Error('Por favor, permita o acesso à sua localização nas configurações do seu navegador e tente novamente.'));
            break;
          case error.POSITION_UNAVAILABLE:
            reject(new Error('Não foi possível obter sua localização. Por favor, verifique se o GPS está ativado e tente novamente.'));
            break;
          case error.TIMEOUT:
            reject(new Error('Tempo esgotado ao tentar obter sua localização. Por favor, verifique se o GPS está ativado e tente novamente.'));
            break;
          default:
            reject(new Error('Ocorreu um erro ao obter sua localização. Por favor, tente novamente.'));
        }
      },
      options
    );
  });
}

export function isWithinStoreRange(latitude: number, longitude: number): boolean {
  return STORE_LOCATIONS.some(store => {
    const distance = calculateDistance(
      latitude,
      longitude,
      store.latitude,
      store.longitude
    );
    return distance <= store.radius;
  });
}

export function getClosestStore(latitude: number, longitude: number): (StoreLocation & { distance?: number }) | null {
  let closestStore: (StoreLocation & { distance?: number }) | null = null;
  let minDistance = Infinity;

  STORE_LOCATIONS.forEach(store => {
    const distance = calculateDistance(
      latitude,
      longitude,
      store.latitude,
      store.longitude
    );
    
    if (distance < minDistance) {
      minDistance = distance;
      closestStore = { ...store, distance };
    }
  });

  return closestStore;
}

export function formatDistance(meters: number): string {
  if (meters < 1000) {
    return `${Math.round(meters)} metros`;
  }
  return `${(meters / 1000).toFixed(1)} km`;
}