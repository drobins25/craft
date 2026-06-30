export interface OrderLike {
  id: number;
}

export class OrderService {
  load(id: number): OrderLike {
    return { id };
  }

  save(order: OrderLike): void {
    void order;
  }
}

export function makeId(prefix: string): number {
  return prefix.length;
}
