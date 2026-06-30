class OrderRepo:
    def load(self, order_id):
        return order_id

    def save(self, order):
        return None


def make_id(prefix):
    return len(prefix)
