using Microsoft.Extensions.DependencyInjection;

namespace AzureFunction.Business
{
    public static class Register
    {
        public static void RegisterServices(IServiceCollection services)
        {
            // Register other services

            // DI - Register DataAccess Services
            DataAccess.Register.RegisterServices(services);
        }
    }
}
