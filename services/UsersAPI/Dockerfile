FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app
EXPOSE 8080

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY ["contracts/FCG.Contracts/FCG.Contracts.csproj", "contracts/FCG.Contracts/"]
COPY ["services/UsersAPI/UsersAPI.csproj", "services/UsersAPI/"]
RUN dotnet restore "services/UsersAPI/UsersAPI.csproj"
COPY . .
RUN dotnet publish "services/UsersAPI/UsersAPI.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM base AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "UsersAPI.dll"]
