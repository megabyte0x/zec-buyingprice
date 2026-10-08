import { Button } from '@/components/ui/button';
export default function LinkButton({href,label='Download .dmg',arrow='↘',variant='default'}:{href:string;label?:string;arrow?:string;variant?:'default'|'outline'}) {
  return <Button asChild size="lg" variant={variant}><a href={href}>{label}<span aria-hidden="true">{arrow}</span></a></Button>;
}
