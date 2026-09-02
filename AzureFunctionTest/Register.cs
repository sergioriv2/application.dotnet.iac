using Microsoft.Extensions.DependencyInjection;

namespace AzureFunctionTest
{
    public static class Register
    {
        public static void RegisterServices(IServiceCollection services)
        {
            // Register other services

            // DI - Register Business Services
            AzureFunction.Business.Register.RegisterServices(services);
        }
    }
}
