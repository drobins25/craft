using Microsoft.Extensions.Logging;

namespace Acme.Data
{
    public class LoadOrdersRepository(ILogger<LoadOrdersRepository> logger, IDbConnection db)
    {
        public async Task<int> Count()
        {
            return await db.QueryAsync();
        }
    }
}
