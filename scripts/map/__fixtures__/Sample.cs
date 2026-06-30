using System.Collections.Generic;
using System.Threading.Tasks;

namespace Acme.Data
{
    public class LoadOrders
    {
        public IEnumerable<int> GenerateIds(int count, string prefix)
        {
            for (var i = 0; i < count; i++) yield return i;
        }

        public IEnumerable<int> GenerateIds(int count)
        {
            return GenerateIds(count, "");
        }

        public async Task<Order> LoadAsync(int id)
        {
            await Task.Delay(1);
            return new Order();
        }
    }

    public class Order
    {
    }
}
