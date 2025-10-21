'use client';

import { upload } from '@vercel/blob/client';
import { useRef, useState } from 'react';

type BlobResult = {
  url: string;
  downloadUrl: string;
  pathname: string;
  contentType?: string;
  contentDisposition: string;
};

export default function UploadWidget() {
  const inputFileRef = useRef<HTMLInputElement>(null);
  const [blob, setBlob] = useState<BlobResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!inputFileRef.current?.files?.length) return;

    const file = inputFileRef.current.files[0];
    try {
      const newBlob = await upload(file.name, file, {
        access: 'public',
        handleUploadUrl: '/api/upload', // our route above
      });
      setBlob(newBlob);
    } catch (err: any) {
      setError(err.message || 'Upload failed');
    }
  }

  return (
    <form onSubmit={onSubmit} className="upload-widget">
      <input ref={inputFileRef} type="file" required />
      <button className="btn btn-primary" type="submit">Upload</button>
      {blob && <p>Uploaded: <a href={blob.url} target="_blank" rel="noreferrer">{blob.url}</a></p>}
      {error && <p className="login-status error">{error}</p>}
    </form>
  );
}
