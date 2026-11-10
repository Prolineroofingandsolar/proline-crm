import { useStorageAsset } from '../lib/useStorageAsset';

export function StorageImage({ locator, ...props }: { locator: string } & Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'src'>) {
  const url = useStorageAsset(locator);
  if (!url) return <div aria-label={props.alt} className={props.className} />;
  return <img {...props} src={url} />;
}
