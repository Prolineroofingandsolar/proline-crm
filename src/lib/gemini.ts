const API_KEY = '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';
const MODEL = 'nvidia/nemotron-nano-12b-v2-vl:free';

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

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            { type: 'image_url', image_url: { url: `data:${file.type};base64,${base64}` } },
          ],
        },
      ],
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as { error?: { message?: string } }).error?.message ?? 'Could not read the image — try again');
  }

  const data = await res.json();
  const text: string = data.choices?.[0]?.message?.content ?? '';

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
