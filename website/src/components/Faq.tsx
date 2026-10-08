import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { faqs } from '@/lib/site';
export default function Faq() {
  return <Accordion type="multiple" defaultValue={faqs.map((_, i) => String(i))}>{faqs.map((faq, i) => <AccordionItem value={String(i)} key={faq.question}><AccordionTrigger>{faq.question}</AccordionTrigger><AccordionContent forceMount>{faq.answer}</AccordionContent></AccordionItem>)}</Accordion>;
}
