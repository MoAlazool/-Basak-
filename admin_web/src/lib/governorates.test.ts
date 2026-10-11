import { describe, expect, it } from 'vitest';
import { governorateNames, sameCodes, type Governorate } from './governorates';

const list: Governorate[] = [
  { code: 'dakahlia', name: 'الدقهلية', sort_order: 12 },
  { code: 'damietta', name: 'دمياط', sort_order: 13 },
  { code: 'gharbia', name: 'الغربية', sort_order: 18 },
];

describe('company governorates', () => {
  it('a choice is a set: order does not matter, a difference does', () => {
    expect(sameCodes(['damietta', 'dakahlia'], ['dakahlia', 'damietta'])).toBe(true);
    expect(sameCodes(['dakahlia'], ['dakahlia', 'damietta'])).toBe(false);
    expect(sameCodes([], [])).toBe(true);
  });

  it('names the chosen ones in list order', () => {
    expect(governorateNames(list, ['gharbia', 'dakahlia'])).toBe('الدقهلية، الغربية');
    expect(governorateNames(list, [])).toBe('');
  });
});
