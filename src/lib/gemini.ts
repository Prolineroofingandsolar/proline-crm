const API_KEY = 'AIzaSyDVDGsvnnvb1-XHCun8SV0K2WU5RJmZawo';
const MODEL = 'gemini-2.0-flash';

export interface ExtractedLead {
  name?: string;
  phone?: string;
  email?: string;
  address?: string;
  jobType?: string;
  notes?: string;
}

function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export async function extractLeadFromImage(file: File): Promise<ExtractedLead> {
  const base64 = await fileToBase64(file);

  const prompt = `Look at this image and extract any customer or job enquiry information you can see.
Return ONLY a JSON object with these fields (use null for anything not found):
{
  "name": "customer full name",
  "phone": "phone number including country code if shown",
  "email": "email address",
  "address": "full address or postcode",
  "jobType": "best match from: Roof Repair, Solar Installation, New Roof, Flat Roof, Solar + Battery, Guttering, Fascias & Soffits, Chimney Repair — or null if unclear",
  "notes": "any other useful details like job description or special requirements"
}
Return only the JSON, no explanation.`;

  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: file.type, data: base64 } },
          ],
        }],
        generationConfig: { temperature: 0.1 },
      }),
    }
  );

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as { error?: { message?: string } }).error?.message ?? 'Gemini API error');
  }

  const data = await res.json();
  const text: string = data.candidates?.[0]?.content?.parts?.[0]?.text ?? '';

  // Strip markdown code fences if present
  const json = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();

  try {
    const parsed = JSON.parse(json);
    return {
      name: parsed.name || undefined,
      phone: parsed.phone || undefined,
      email: parsed.email || undefined,
      address: parsed.address || undefined,
      jobType: parsed.jobType || undefined,
      notes: parsed.notes || undefined,
    };
  } catch {
    throw new Error('Could not read the image — try a clearer photo');
  }
}
