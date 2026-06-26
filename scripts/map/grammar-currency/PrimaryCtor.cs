using Microsoft.Extensions.Logging;

namespace AGP.Data
{
    public class LoadOrdersRepository(ILogger<LoadOrdersRepository> logger, IDbConnection db)
    {
        public async Task<int> Count()
        {
            return await db.QueryAsync();
        }
    }
}
