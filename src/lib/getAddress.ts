const API_KEY = 'cIZZPCzx-UCBob0_Vxj8RA52073';

export interface AddressSuggestion {
  address: string;
  id: string;
}

export async function autocompleteAddress(input: string): Promise<AddressSuggestion[]> {
  try {
    const res = await fetch(
      `https://api.getaddress.io/autocomplete/${encodeURIComponent(input)}?api-key=${API_KEY}`
    );
    if (!res.ok) return [];
    const data = await res.json();
    return data.suggestions ?? [];
  } catch {
    return [];
  }
}

export async function getFullAddress(id: string): Promise<string> {
  try {
    const res = await fetch(`https://api.getaddress.io/get/${id}?api-key=${API_KEY}`);
    if (!res.ok) return '';
    const d = await res.json();
    const parts = [d.line_1, d.line_2, d.line_3, d.locality, d.town_or_city, d.postcode].filter(Boolean);
    return parts.join(', ');
  } catch {
    return '';
  }
}
