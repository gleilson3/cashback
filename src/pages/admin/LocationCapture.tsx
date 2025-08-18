import { useState, useEffect } from 'react';
import { MapPin, Copy, CheckCircle2, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { supabase } from '../../lib/supabase';
import { STORE_LOCATIONS } from '../../types';

export default function LocationCapture() {
  const [location, setLocation] = useState<GeolocationPosition | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [updating, setUpdating] = useState(false);

  const getCurrentLocation = async () => {
    setLoading(true);
    setError(null);

    try {
      if (!navigator.geolocation) {
        throw new Error('Geolocalização não é suportada pelo seu navegador');
      }

      const position = await new Promise<GeolocationPosition>((resolve, reject) => {
        navigator.geolocation.getCurrentPosition(
          resolve,
          reject,
          {
            enableHighAccuracy: true,
            timeout: 10000,
            maximumAge: 0
          }
        );
      });

      setLocation(position);
      toast.success('Localização obtida com sucesso!');
    } catch (error: any) {
      const errorMessage = error.code === 1 ? 
        'Permissão de localização negada. Por favor, permita o acesso à localização.' :
        error.code === 2 ?
        'Localização indisponível. Verifique se o GPS está ativado.' :
        error.code === 3 ?
        'Tempo esgotado ao obter localização.' :
        'Erro ao obter localização: ' + error.message;
      
      setError(errorMessage);
      toast.error(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  const updateTestStoreLocation = async () => {
    if (!location) return;

    setUpdating(true);
    try {
      // Update store in database
      const { error } = await supabase
        .from('stores')
        .update({
          address: `Localização Atual - ${location.coords.latitude.toFixed(6)}, ${location.coords.longitude.toFixed(6)}`
        })
        .eq('code', 'TESTE');

      if (error) throw error;

      toast.success('Coordenadas da loja teste atualizadas no banco de dados!');
    } catch (error: any) {
      console.error('Error updating store location:', error);
      toast.error('Erro ao atualizar localização da loja: ' + error.message);
    } finally {
      setUpdating(false);
    }
  };

  const copyCoordinates = (lat: number, lng: number) => {
    const coordText = `${lat}, ${lng}`;
    navigator.clipboard.writeText(coordText);
    toast.success('Coordenadas copiadas!');
  };

  const formatCoordinates = (lat: number, lng: number) => {
    return {
      decimal: `${lat.toFixed(6)}, ${lng.toFixed(6)}`,
      dms: convertToDMS(lat, lng)
    };
  };

  const convertToDMS = (lat: number, lng: number) => {
    const latDMS = convertDecimalToDMS(Math.abs(lat), lat >= 0 ? 'N' : 'S');
    const lngDMS = convertDecimalToDMS(Math.abs(lng), lng >= 0 ? 'E' : 'W');
    return `${latDMS} ${lngDMS}`;
  };

  const convertDecimalToDMS = (decimal: number, direction: string) => {
    const degrees = Math.floor(decimal);
    const minutes = Math.floor((decimal - degrees) * 60);
    const seconds = ((decimal - degrees) * 60 - minutes) * 60;
    return `${degrees}°${minutes}'${seconds.toFixed(1)}"${direction}`;
  };

  return (
    <div className="max-w-2xl mx-auto">
      <div className="glass-card p-8">
        <h1 className="text-2xl font-bold text-gray-900 mb-6 flex items-center gap-2">
          <MapPin className="w-6 h-6 text-purple-600" />
          Capturar Localização para Loja Teste
        </h1>

        <div className="space-y-6">
          <div className="text-center">
            <button
              onClick={getCurrentLocation}
              disabled={loading}
              className="btn-primary flex items-center gap-2 mx-auto"
            >
              <MapPin className="w-5 h-5" />
              {loading ? 'Obtendo localização...' : 'Obter Minha Localização'}
            </button>
          </div>

          {error && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-4 flex items-start gap-3">
              <AlertCircle className="w-5 h-5 text-red-600 mt-0.5" />
              <div>
                <h3 className="font-medium text-red-800">Erro ao obter localização</h3>
                <p className="text-red-700 text-sm mt-1">{error}</p>
              </div>
            </div>
          )}

          {location && (
            <div className="bg-green-50 border border-green-200 rounded-lg p-6">
              <h3 className="font-medium text-green-800 mb-4 flex items-center gap-2">
                <CheckCircle2 className="w-5 h-5" />
                Localização Obtida
              </h3>
              
              <div className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Coordenadas Decimais
                  </label>
                  <div className="flex items-center gap-2">
                    <input
                      type="text"
                      value={formatCoordinates(location.coords.latitude, location.coords.longitude).decimal}
                      readOnly
                      className="input-field bg-gray-50"
                    />
                    <button
                      onClick={() => copyCoordinates(location.coords.latitude, location.coords.longitude)}
                      className="btn-secondary py-3 px-4"
                      title="Copiar coordenadas"
                    >
                      <Copy className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Coordenadas DMS
                  </label>
                  <input
                    type="text"
                    value={formatCoordinates(location.coords.latitude, location.coords.longitude).dms}
                    readOnly
                    className="input-field bg-gray-50"
                  />
                </div>

                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Latitude
                    </label>
                    <input
                      type="text"
                      value={location.coords.latitude.toFixed(6)}
                      readOnly
                      className="input-field bg-gray-50"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      Longitude
                    </label>
                    <input
                      type="text"
                      value={location.coords.longitude.toFixed(6)}
                      readOnly
                      className="input-field bg-gray-50"
                    />
                  </div>
                </div>

                <div className="grid grid-cols-2 gap-4 text-sm text-gray-600">
                  <div>
                    <span className="font-medium">Precisão:</span> ±{location.coords.accuracy.toFixed(0)}m
                  </div>
                  {location.coords.altitude && (
                    <div>
                      <span className="font-medium">Altitude:</span> {location.coords.altitude.toFixed(0)}m
                    </div>
                  )}
                </div>

                <button
                  onClick={updateTestStoreLocation}
                  disabled={updating}
                  className="btn-primary w-full"
                >
                  {updating ? 'Atualizando...' : 'Atualizar Loja Teste com Esta Localização'}
                </button>
              </div>
            </div>
          )}

          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h3 className="font-medium text-blue-800 mb-2">Instruções</h3>
            <ol className="text-blue-700 text-sm space-y-1">
              <li>1. Clique em "Obter Minha Localização"</li>
              <li>2. Permita o acesso à localização quando solicitado</li>
              <li>3. Verifique se as coordenadas estão corretas</li>
              <li>4. Clique em "Atualizar Loja Teste" para salvar</li>
            </ol>
          </div>
        </div>
      </div>
    </div>
  );
}