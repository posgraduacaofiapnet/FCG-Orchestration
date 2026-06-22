FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["contracts/FCG.Contracts/FCG.Contracts.csproj", "contracts/FCG.Contracts/"]
COPY ["services/PaymentsAPI/PaymentsAPI.csproj", "services/PaymentsAPI/"]
RUN dotnet restore "services/PaymentsAPI/PaymentsAPI.csproj"
COPY . .
RUN dotnet publish "services/PaymentsAPI/PaymentsAPI.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "PaymentsAPI.dll"]
